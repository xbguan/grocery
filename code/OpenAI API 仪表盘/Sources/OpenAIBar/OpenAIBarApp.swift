import SwiftUI
import AppKit
import Combine

// MARK: - 预览窗口（仅 --demo 参数时使用）

enum DemoWindow {
    private static var retained: NSWindow?

    @MainActor
    static func show() {
        let args = CommandLine.arguments
        let model = AppModel(demo: true)
        if args.contains("--demo-empty") { model.loadDemoEmpty() }
        if args.contains("--demo-credit") { model.loadDemoCredit() }
        if args.contains("--demo-credit-login") { model.loadDemoCreditLogin() }
        if args.contains("--demo-credit-expired") { model.loadDemoCreditExpired() }
        if args.contains("--demo-subscription") { model.loadDemoSubscription() }

        let page: MenuContentView.Page = args.contains("--demo-settings") ? .settings
            : (args.contains("--demo-subscription") ? .subscription : .usage)
        let hosting = NSHostingView(rootView: MenuContentView(initialPage: page).environmentObject(model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: UI.panelWidth, height: UI.panelHeight),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "OpenAI 仪表盘 · 预览（假数据）"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: args.contains("--demo-dark") ? .darkAqua : .aqua)
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        retained = window
    }
}

// MARK: - 菜单栏与主窗口

/// 保留标准标题栏按钮；点关闭或按 Command-W 时只隐藏主窗口。
private final class DashboardWindow: NSWindow {
    override func performClose(_ sender: Any?) {
        orderOut(sender)
    }
}

@MainActor
final class DashboardAppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusItem: NSStatusItem?
    private var dashboardWindow: DashboardWindow?
    private var iconSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 让菜单栏图标尽量靠在右侧（系统默认会把新图标插到最左边）
        UserDefaults.standard.register(defaults: [
            "NSStatusItem Preferred Position Item-0": 320.0
        ])

        let demo = CommandLine.arguments.contains("--demo")
        let model = demo ? AppModel(demo: true) : AppModel()
        self.model = model

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        statusItem.button?.toolTip = "OpenAI 仪表盘"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showDashboard)
        iconSubscription = model.$errorKind.sink { [weak self] errorKind in
            self?.updateIcon(for: errorKind)
        }

        if demo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                DemoWindow.show()
            }
        }
    }

    private func updateIcon(for errorKind: ErrorKind?) {
        switch errorKind {
        case .some(.noKey): statusItem?.button?.image = MenuBarIcon.idle()
        case .some:         statusItem?.button?.image = MenuBarIcon.alert()
        case .none:         statusItem?.button?.image = MenuBarIcon.dial()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return true
    }

    @objc private func showDashboard() {
        guard let model else { return }
        let window: DashboardWindow
        if let existing = dashboardWindow {
            window = existing
        } else {
            let created = DashboardWindow(
                contentRect: NSRect(x: 0, y: 0, width: UI.panelWidth, height: UI.panelHeight),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            created.title = "OpenAI 仪表盘"
            created.isReleasedWhenClosed = false
            created.contentView = NSHostingView(rootView: MenuContentView().environmentObject(model))
            dashboardWindow = created
            window = created
        }

        if !window.isVisible { model.refreshCreditOnPanelOpen() }
        if window.isMiniaturized { window.deminiaturize(nil) }
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2,
                                          y: frame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - App

@main
struct OpenAIBarApp: App {
    @NSApplicationDelegateAdaptor(DashboardAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) { }
            }
    }
}
