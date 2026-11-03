import SwiftUI
import AppKit

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

// MARK: - App

@main
struct OpenAIBarApp: App {
    @StateObject private var model: AppModel

    init() {
        // 让菜单栏图标尽量靠在右侧（系统默认会把新图标插到最左边）
        UserDefaults.standard.register(defaults: [
            "NSStatusItem Preferred Position Item-0": 320.0
        ])

        let demo = CommandLine.arguments.contains("--demo")
        // 演示模式用假数据，不读取个人配置
        _model = StateObject(wrappedValue: demo ? AppModel(demo: true) : AppModel())

        if demo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                DemoWindow.show()
            }
        }

    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
        } label: {
            MenuBarLabel()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
