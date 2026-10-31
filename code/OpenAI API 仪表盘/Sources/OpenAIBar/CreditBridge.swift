import AppKit
import Foundation
import WebKit

/// 余额读取桥。
///
/// 背景（2026-10 实测）：
/// * `GET /v1/dashboard/billing/credit_grants` 是唯一能给「剩余额度」的接口，
///   但任何 `sk-` / `sk-admin-` 密钥请求它都会 403：
///   "must be made with a session key (that is, it can only be made from the browser)"
/// * 只要带上平台登录态（浏览器会话），同一个接口返回 200：
///   {"total_granted":16.0,"total_used":3.49,"total_available":12.51,...}
///
/// 所以这里不保存任何密码，也不保存 cookie 明文：用一个隐藏的 WKWebView 打开平台账单页，
/// 让页面自己发那个请求，我们在 documentStart 注入钩子把**响应体**截下来。
///
/// 关键约束：不能自己发这个请求。从页面上下文 fetch api.openai.com 会被 CORS 挡掉
/// （实测报 "Load failed"），所以只能「截」不能「发」。
@MainActor
final class CreditBridge: NSObject {

    enum State: Equatable {
        case off            // 未启用
        case idle           // 启用但未开始
        case loading        // 正在加载平台页
        case needsLogin     // 登录态失效，需要用户登录
        case ready          // 已拿到余额
        case failed(String) // 网络 / 解析失败
    }

    /// 状态变化回调（AppModel 用它同步到 @Published）
    var onChange: (() -> Void)?

    private(set) var state: State = .off { didSet { if state != oldValue { onChange?() } } }
    private(set) var available: Double? { didSet { if available != oldValue { onChange?() } } }
    private(set) var granted: Double?
    private(set) var used: Double?
    private(set) var updatedAt: Date? { didSet { if updatedAt != oldValue { onChange?() } } }

    /// 最近一次成功读到的值。**只用于「上次读到 X」这类文案**，不参与现值渲染：
    /// 否则会话过期后会一直拿旧数字当当前余额显示（1.3.1 之前就是这个 bug）。
    private(set) var lastKnown: (available: Double, granted: Double?, used: Double?, at: Date)?

    /// 平台账单页：这个页面自己会请求 credit_grants
    static let pageURL = URL(string: "https://platform.openai.com/settings/organization/billing/overview")!

    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var timeoutTimer: Timer?
    private var settleTimer: Timer?
    private var lastLoadAt: Date?
    private var hasStarted = false
    /// 世代号：每次 start()/stop() 递增。异步回调（clearSession）凭它判断
    /// 「在我等待期间世界是不是已经变了」，变了就作废，避免把当前状态改乱。
    private var generation = 0

    // MARK: 生命周期

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        generation += 1
        state = .idle
        load()
    }

    func stop() {
        generation += 1
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        settleTimer?.invalidate()
        settleTimer = nil
        hostWindow?.orderOut(nil)
        hostWindow?.contentView = nil
        hostWindow = nil
        webView?.stopLoading()
        webView = nil
        hasStarted = false
        state = .off
        available = nil
        granted = nil
        used = nil
        updatedAt = nil
    }

    /// 刷新余额。stale 是「多久之内算新鲜」，避免每次开面板都整页加载。
    func refresh(stale seconds: TimeInterval = 900) {
        guard hasStarted else { return }
        if state == .loading { return }
        // 有值：按 stale 走；没值（上次失败）：至少隔 60s 再试，否则每次刷新都重来一遍，
        // 面板会不停在「正在读取 → 失败 → 正在读取」之间跳。
        let floor: TimeInterval = available == nil ? 60 : seconds
        if let last = lastLoadAt, Date().timeIntervalSince(last) < floor { return }
        load()
    }

    /// 面板每次打开时叫一下：如果卡在 loading 太久（菜单弹出期间 run loop 处于跟踪模式，
    /// 定时器可能迟迟不跑），主动重来一次，别让它一直转圈。
    func recoverIfStuck(_ seconds: TimeInterval = 45) {
        guard hasStarted, state == .loading, let last = lastLoadAt else { return }
        if Date().timeIntervalSince(last) > seconds { load() }
    }

    /// 强制重载（用户点「重试」）
    func forceReload() {
        guard hasStarted else { return }
        load()
    }

    // MARK: 加载

    private func load() {
        let view = ensureWebView()
        lastLoadAt = Date()
        state = .loading
        view.load(URLRequest(url: Self.pageURL))

        timeoutTimer?.invalidate()
        settleTimer?.invalidate()
        // 必须显式加进 .common 模式：菜单栏面板展开时 run loop 在 eventTracking 模式，
        // scheduledTimer 默认只进 .default，超时永远不会触发 → 界面永久停在「正在读取」。
        let t = Timer(timeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .loading else { return }
                self.state = .failed("读取超时")
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timeoutTimer = t
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }

        let cfg = WKWebViewConfiguration()
        // 用默认存储：登录态落在 App 自己的 WebKit 容器里，重启后仍有效
        cfg.websiteDataStore = .default()
        cfg.userContentController.add(self, name: "credit")
        cfg.userContentController.addUserScript(
            WKUserScript(source: Self.hookJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 980, height: 760), configuration: cfg)
        view.navigationDelegate = self

        // 不挂在屏幕上，但要挂在一个真实窗口里 —— 完全无窗口的 WebView 会被节流，
        // 页面里的 setInterval / 懒加载可能不跑。
        let win = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 980, height: 760),
                           styleMask: [.borderless],
                           backing: .buffered, defer: false)
        win.contentView = view
        win.orderFrontRegardless()

        webView = view
        hostWindow = win
        return view
    }

    // MARK: 结果处理

    private func apply(summary: CreditSummary, from url: String) {
        granted = summary.totalGranted
        used = summary.totalUsed
        available = summary.totalAvailable
        updatedAt = .now
        if let a = summary.totalAvailable {
            lastKnown = (a, summary.totalGranted, summary.totalUsed, .now)
        }
        state = .ready
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        settleTimer?.invalidate()
        settleTimer = nil
        NSLog("OpenAIBar: credit \(summary.totalAvailable) via \(url)")
    }

    private func apply(domValue: Double) {
        available = domValue
        updatedAt = .now
        lastKnown = (domValue, nil, nil, .now)
        state = .ready
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        settleTimer?.invalidate()
        settleTimer = nil
    }

    /// 登录态清除（设置里「退出登录」）
    func clearSession(_ done: (() -> Void)? = nil) {
        let gen = generation
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // 清理期间发生过 stop()/start()（比如用户「关掉又马上打开」）：
                // 本次清理结果作废，别把正在进行的加载状态改乱。
                guard self.generation == gen else { return }
                self.available = nil
                self.granted = nil
                self.used = nil
                self.updatedAt = nil
                self.lastKnown = nil
                self.lastLoadAt = nil
                // 开关仍开着（= 在设置里点「退出登录」而不是关开关）→ 回到「需要登录」，
                // 否则会停在 .idle，界面永远显示「正在读取余额…」。
                if self.hasStarted { self.state = .needsLogin }
                done?()
            }
        }
    }

    // MARK: 注入脚本

    private static let hookJS = """
    (function(){
      if (window.__oaiCreditHooked) return;
      window.__oaiCreditHooked = true;

      function send(payload){
        try { window.webkit.messageHandlers.credit.postMessage(payload); } catch (e) {}
      }
      function isCreditURL(u){
        return typeof u === 'string' && u.indexOf('/dashboard/billing/credit_grants') >= 0;
      }

      // 1) fetch 钩子：页面发请求后，复制一份响应体读出来
      var origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function(){
          var a = arguments[0];
          var u = (typeof a === 'string') ? a : ((a && a.url) || '');
          var p = origFetch.apply(this, arguments);
          if (isCreditURL(u)) {
            p.then(function(r){
              try {
                r.clone().text().then(function(t){ send({url: u, status: r.status, body: String(t).slice(0, 6000)}); })
                             .catch(function(){});
              } catch (e) {}
            }).catch(function(){});
          }
          return p;
        };
      }

      // 2) XHR 钩子：兜住走 XMLHttpRequest 的实现
      var origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(m, u){
        this.__oaiURL = u;
        return origOpen.apply(this, arguments);
      };
      var origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function(){
        var self = this;
        this.addEventListener('load', function(){
          if (isCreditURL(self.__oaiURL)) {
            send({url: String(self.__oaiURL), status: self.status, body: String(self.responseText || '').slice(0, 6000)});
          }
        });
        return origSend.apply(this, arguments);
      };

      // 3) DOM 兜底：接口改版时，至少还能从页面文字里读「Credit remaining $12.51」
      var scans = 0;
      var timer = setInterval(function(){
        scans++;
        try {
          var t = document.body ? document.body.innerText : '';
          var m = t.match(/Credit remaining\\s*\\$?\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)/i);
          if (m) send({url: 'dom', body: m[1].replace(/,/g, '')});
        } catch (e) {}
        if (scans > 20) clearInterval(timer);
      }, 2000);
    })();
    """
}

// MARK: - 消息与导航

extension CreditBridge: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let url = dict["url"] as? String,
              let body = dict["body"] as? String else { return }

        if url == "dom" {
            if let v = Double(body) { apply(domValue: v) }
            return
        }
        // 会话过期最常见的形态不是整页跳登录页，而是页面正常、只有余额接口 401/403。
        // 这种情况以前只能等 30s 超时 → 被误报成「读取超时」，现在直接判为需要重新登录。
        let status = dict["status"] as? Int ?? 0
        if status == 401 || status == 403 {
            timeoutTimer?.invalidate()
            timeoutTimer = nil
            settleTimer?.invalidate()
            settleTimer = nil
            state = .needsLogin
            NSLog("OpenAIBar: credit session expired (HTTP \(status))")
            return
        }
        guard let data = body.data(using: .utf8),
              let summary = try? JSONDecoder().decode(CreditSummary.self, from: data) else { return }
        apply(summary: summary, from: url)
    }
}

extension CreditBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 已经拿到数据或已判定登录失效，就不再往下走
        guard state == .loading else { return }
        let href = webView.url?.absoluteString ?? ""
        if href.contains("/login") || href.contains("auth.openai.com") {
            state = .needsLogin
            timeoutTimer?.invalidate()
            timeoutTimer = nil
            settleTimer?.invalidate()
            settleTimer = nil
            return
        }
        // 页面加载完成但还没截到 credit_grants：给页面 JS 几秒发请求，
        // 若仍无数据则判为「需要登录」。否则未登录 / 会话失效时页面可能
        // 停在中间态，既不跳登录页也不发余额请求，界面会永远卡在「正在读取」。
        scheduleSettle()
    }

    /// 页面加载完后给一个「数据落定」宽限期：几秒内没拿到余额就判需要登录。
    private func scheduleSettle() {
        settleTimer?.invalidate()
        let t = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .loading else { return }
                self.state = .needsLogin
                self.timeoutTimer?.invalidate()
                self.timeoutTimer = nil
                NSLog("OpenAIBar: credit no data after page load -> needsLogin")
            }
        }
        RunLoop.main.add(t, forMode: .common)
        settleTimer = t
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        settleTimer?.invalidate()
        settleTimer = nil
        state = .failed(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // 用户在登录窗口里操作时，这里失败不应打断整页加载
        if (error as NSError).code == NSURLErrorCancelled { return }
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        settleTimer?.invalidate()
        settleTimer = nil
        state = .failed(error.localizedDescription)
    }
}

// MARK: - 数据结构

struct CreditSummary: Decodable {
    let totalGranted: Double?
    let totalUsed: Double?
    let totalAvailable: Double?

    enum CodingKeys: String, CodingKey {
        case totalGranted = "total_granted"
        case totalUsed = "total_used"
        case totalAvailable = "total_available"
    }
}

// MARK: - 登录窗口
//
// 登录必须由用户自己在窗口里完成（账号密码 / 验证码 / MFA 我们不碰）。
// 窗口里的 WebView 与隐藏 WebView 共用 .default() 存储，登录完 cookie 立刻互通。

@MainActor
enum CreditLoginWindow {
    private static var retained: NSWindow?
    private static var watcher: LoginWatcher?

    static func show(onFinished: @escaping () -> Void) {
        if let w = retained {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 760), configuration: cfg)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "登录 OpenAI 平台（仅用于读取余额，登录态只存在本机）"
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let w = LoginWatcher { [weak window] in
            window?.orderOut(nil)
            window?.close()
            retained = nil
            watcher = nil
            onFinished()
        }
        view.navigationDelegate = w
        window.delegate = w
        w.onClosed = {
            // 用户手动关窗（windowWillClose 触发，且没走到登录成功）：清引用 + 重查一次
            retained = nil
            watcher = nil
            onFinished()
        }
        watcher = w
        retained = window

        view.load(URLRequest(url: CreditBridge.pageURL))
    }

    static func close() {
        retained?.orderOut(nil)
        retained?.close()
        retained = nil
        watcher = nil
    }
}

@MainActor
final class LoginWatcher: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private let onSuccess: () -> Void
    var onClosed: (() -> Void)?
    private(set) var fired = false

    /// 是否真的经过登录页（auth.openai.com / /login）。
    ///
    /// 这个标记是 1.3.8 修 bug 的关键：未登录时打开账单页，SPA 会先完成一次
    /// platform.openai.com 的加载、再由 JS 跳到 auth.openai.com。只看「当前是 platform 域名」
    /// 会把这次初次加载当成登录成功，窗口 1.2 秒后自己关掉 —— 用户根本没机会登录。
    private var sawAuth = false

    init(onSuccess: @escaping () -> Void) {
        self.onSuccess = onSuccess
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !fired, let url = webView.url else { return }
        let href = url.absoluteString
        let path = url.path

        // 1) 见到登录页 → 记下「用户确实需要登录」，继续等他登完
        if href.contains("auth.openai.com")
            || path.hasPrefix("/login") || path.hasPrefix("/log-in")
            || path.contains("/auth/") || path.contains("/authorize") {
            sawAuth = true
            return
        }

        // 2) 必须落在平台内部，且此前经过登录页，才算登录完成
        guard href.hasPrefix("https://platform.openai.com"), sawAuth else { return }

        // 3) OAuth 回调中转页还没走完，再等等
        if let q = url.query, q.contains("callback") || q.contains("redirect") { return }

        fired = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.onSuccess() }
    }

    /// 用户手动点关闭（没走到登录成功的 onSuccess）也要收尾：
    /// 之前 onClosed 闭包被赋值却从没人调用，等于手动关窗后残留引用、也不触发重查。
    func windowWillClose(_ notification: Notification) {
        if !fired { onClosed?() }
    }
}
