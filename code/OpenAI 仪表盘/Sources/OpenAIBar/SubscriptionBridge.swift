import AppKit
import Foundation
import WebKit

@MainActor
final class SubscriptionBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    enum State: Equatable {
        case off
        case loading
        case needsLogin
        case ready
        case failed(String)
    }

    var onChange: (() -> Void)?
    private(set) var state: State = .off { didSet { onChange?() } }
    private(set) var snapshot: SubscriptionSnapshot? { didSet { onChange?() } }
    var isLoginWindowOpen: Bool { loginWindow != nil }

    static let pageURL = URL(string: "https://chatgpt.com/settings/usage")!
    static let loginURL = URL(string: "https://chatgpt.com/auth/login?next=%2Fsettings%2Fusage")!
    private static let analyticsURL = URL(string: "https://chatgpt.com/settings/usage?tab=analytics")!
    private static let storeID = UUID(uuidString: "B27C8B49-EC7A-4E5F-A5D8-2AC31F02773B")!
    private let store = WKWebsiteDataStore(forIdentifier: storeID)
    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var loginWindow: NSWindow?
    private var loginView: WKWebView?
    private var timeout: Timer?
    private var lastLoad: Date?
    private var enabled = false
    private var clearingSession = false

    func start() {
        guard !enabled, !clearingSession else { return }
        enabled = true
    }

    func stop() {
        enabled = false
        timeout?.invalidate()
        timeout = nil
        loginWindow?.close()
        loginWindow = nil
        loginView?.stopLoading()
        loginView = nil
        hostWindow?.orderOut(nil)
        hostWindow?.contentView = nil
        hostWindow = nil
        webView?.stopLoading()
        webView = nil
        snapshot = nil
        state = .off
    }

    func refresh(force: Bool = false) {
        guard enabled else { return }
        if !force && (state == .loading || state == .needsLogin || loginWindow != nil) { return }
        if !force, let lastLoad, Date().timeIntervalSince(lastLoad) < 60 { return }
        lastLoad = .now
        state = .loading
        let view = ensureWebView()
        view.load(URLRequest(url: Self.pageURL))
        timeout?.invalidate()
        let timer = Timer(timeInterval: 45, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .loading else { return }
                self.state = self.snapshot?.hasQuota == true ? .ready : .needsLogin
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timeout = timer
    }

    func showLogin() {
        guard enabled else { return }
        if let loginWindow {
            loginWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = makeWebView()
        view.navigationDelegate = self
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "登录 ChatGPT（仅用于订阅用量，登录态只存在本机）"
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        loginView = view
        loginWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        view.load(URLRequest(url: Self.loginURL))
    }

    func logout() {
        stop()
        clearingSession = true
        state = .loading
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastLoad = nil
                self.clearingSession = false
                self.state = .off
            }
        }
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.userContentController.add(self, name: "subscription")
        config.userContentController.addUserScript(
            WKUserScript(source: Self.hookJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 760), configuration: config)
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let view = makeWebView()
        view.navigationDelegate = self
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1000, height: 760),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        webView = view
        hostWindow = window
        return view
    }

    static func analyticsPage(afterResponse path: String, at url: URL?) -> URL? {
        path == "/backend-api/wham/usage" && url == pageURL ? analyticsURL : nil
    }

    static func hasFreshQuota(afterResponse path: String, snapshot: SubscriptionSnapshot) -> Bool {
        path == "/backend-api/wham/usage" && snapshot.hasQuota
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard enabled, let item = message.body as? [String: Any],
              let path = item["path"] as? String else { return }
        let status = item["status"] as? Int ?? 0
        if (status == 401 || status == 403) && path == "/backend-api/wham/usage" {
            snapshot = nil
            state = .needsLogin
            timeout?.invalidate()
            return
        }
        guard status == 200, let body = item["body"] as? String else { return }
        var value = snapshot ?? SubscriptionSnapshot()
        guard value.applyWebResponse(path: path, body: body) else { return }
        snapshot = value
        if Self.hasFreshQuota(afterResponse: path, snapshot: value) {
            timeout?.invalidate()
            timeout = nil
            state = .ready
            if loginWindow != nil {
                loginWindow?.close()
                loginWindow = nil
                loginView = nil
                refresh(force: true)
            } else if let analyticsURL = Self.analyticsPage(afterResponse: path, at: message.webView?.url) {
                message.webView?.load(URLRequest(url: analyticsURL))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard enabled, loginWindow == nil else { return }
        let url = webView.url
        if url?.host == "auth.openai.com" || url?.path.hasPrefix("/login") == true {
            timeout?.invalidate()
            state = .needsLogin
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard enabled, (error as NSError).code != NSURLErrorCancelled else { return }
        state = .failed(error.localizedDescription)
    }

    func windowWillClose(_ notification: Notification) {
        loginView?.stopLoading()
        loginWindow = nil
        loginView = nil
        if snapshot?.hasQuota != true && webView == nil { state = .needsLogin }
        onChange?()
    }

    private static let hookJS = """
    (function () {
      if (window.__dashboardSubscriptionHooked) return;
      window.__dashboardSubscriptionHooked = true;
      const allowed = new Set([
        '/backend-api/wham/usage',
        '/backend-api/wham/rate-limit-reset-credits',
        '/backend-api/wham/analytics/daily-workspace-usage-counts',
        '/backend-api/wham/usage/daily-token-usage-breakdown',
        '/backend-api/wham/analytics/daily-plugin-usage-metrics',
        '/backend-api/wham/analytics/daily-skill-usage-metrics'
      ]);
      function pathOf(input) {
        try {
          const url = new URL(typeof input === 'string' ? input : input.url, location.href);
          return url.origin === 'https://chatgpt.com' && allowed.has(url.pathname) ? url.pathname : null;
        } catch (_) { return null; }
      }
      function send(path, status, body) {
        try {
          window.webkit.messageHandlers.subscription.postMessage({
            path: path, status: status, body: String(body).slice(0, 2000000)
          });
        } catch (_) {}
      }
      const originalFetch = window.fetch;
      window.fetch = function () {
        const path = pathOf(arguments[0]);
        const result = originalFetch.apply(this, arguments);
        if (path) result.then(function (response) {
          response.clone().text().then(function (body) {
            send(path, response.status, body);
          }).catch(function () {});
        }).catch(function () {});
        return result;
      };
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__dashboardPath = pathOf(url);
        return originalOpen.apply(this, arguments);
      };
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function () {
        const request = this;
        if (request.__dashboardPath) request.addEventListener('load', function () {
          send(request.__dashboardPath, request.status, request.responseText || '');
        });
        return originalSend.apply(this, arguments);
      };
      let selected = 0, attempts = 0;
      const selectThirtyDays = setInterval(function () {
        attempts++;
        const buttons = Array.from(document.querySelectorAll('button,[role="radio"]'))
          .filter(function (button) { return /^30\\s*(天|days?)$/i.test(button.textContent.trim()); });
        if (buttons.length >= 3 && selected < 3) buttons[selected++].click();
        if (selected >= 3 || attempts >= 40) clearInterval(selectThirtyDays);
      }, 1000);
    })();
    """
}
