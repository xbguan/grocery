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

    /// 平台账单页：这个页面自己会请求 credit_grants
    static let pageURL = URL(string: "https://platform.openai.com/settings/organization/billing/overview")!

    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var timeoutTimer: Timer?
    private var lastLoadAt: Date?
    private var hasStarted = false

    // MARK: 生命周期

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        state = .idle
        load()
    }

    func stop() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
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
        if let last = lastLoadAt, Date().timeIntervalSince(last) < seconds, available != nil { return }
        load()
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
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .loading else { return }
                self.state = .failed("读取超时")
            }
        }
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
        state = .ready
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        NSLog("OpenAIBar: credit \(summary.totalAvailable) via \(url)")
    }

    private func apply(domValue: Double) {
        available = domValue
        updatedAt = .now
        state = .ready
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    /// 登录态清除（设置里「退出登录」）
    func clearSession(_ done: (() -> Void)? = nil) {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.available = nil
                self.granted = nil
                self.used = nil
                self.updatedAt = nil
                self.lastLoadAt = nil
                self.state = self.hasStarted ? .idle : .off
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
                r.clone().text().then(function(t){ send({url: u, body: String(t).slice(0, 6000)}); })
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
            send({url: String(self.__oaiURL), body: String(self.responseText || '').slice(0, 6000)});
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
        guard let data = body.data(using: .utf8),
              let summary = try? JSONDecoder().decode(CreditSummary.self, from: data) else { return }
        apply(summary: summary, from: url)
    }
}

extension CreditBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let href = webView.url?.absoluteString ?? ""
        if href.contains("/login") || href.contains("auth.openai.com") {
            state = .needsLogin
            timeoutTimer?.invalidate()
            timeoutTimer = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        state = .failed(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // 用户在登录窗口里操作时，这里失败不应打断整页加载
        if (error as NSError).code == NSURLErrorCancelled { return }
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
        w.onClosed = { [weak window] in
            // 用户手动关窗（没登录成功）也收尾，避免残留引用
            guard let window, !window.isVisible else { return }
            retained = nil
            watcher = nil
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
final class LoginWatcher: NSObject, WKNavigationDelegate {
    private let onSuccess: () -> Void
    var onClosed: (() -> Void)?
    private var fired = false

    init(onSuccess: @escaping () -> Void) {
        self.onSuccess = onSuccess
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !fired else { return }
        let href = webView.url?.absoluteString ?? ""
        // 回到平台内部且不是登录页 → 说明已经登录成功
        if href.hasPrefix("https://platform.openai.com"),
           !href.contains("/login"),
           !href.contains("/auth/") {
            fired = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.onSuccess() }
        }
    }
}
