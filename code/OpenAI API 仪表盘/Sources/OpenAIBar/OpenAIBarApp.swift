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
        if args.contains("--demo-credit-login") {
            model.update { $0.showCredit = true }
            model.loadDemoCreditLogin()
        }

        let hosting = NSHostingView(rootView: MenuContentView().environmentObject(model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: UI.panelWidth, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenAI API 仪表盘 · 预览（假数据）"
        window.titlebarAppearsTransparent = true
        if args.contains("--demo-dark") {
            window.appearance = NSAppearance(named: .darkAqua)
        }
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        retained = window

        // 等内容测量完再贴合窗口，保证预览图里没有被裁掉的部分
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            hosting.layoutSubtreeIfNeeded()
            let fit = hosting.fittingSize
            guard fit.height > 100 else { return }
            var f = window.frame
            let top = f.maxY
            f.size = NSSize(width: max(fit.width, UI.panelWidth), height: fit.height + 28)
            f.origin.y = top - f.height
            window.setFrame(f, display: true)

            // 固定位置，方便截图
            if let screen = NSScreen.main {
                let topY = screen.visibleFrame.maxY - 8
                window.setFrameOrigin(NSPoint(x: 140, y: topY - f.height))
            }
        }
    }

    /// 预览设置窗口
    @MainActor
    static func showSettings() {
        let model = AppModel(demo: true)
        let hosting = NSHostingView(rootView: SettingsView().environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "设置 · 预览"
        window.contentView = hosting
        window.center()
        if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: 140, y: screen.visibleFrame.maxY - 8 - window.frame.height))
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        retained = window
    }
}

// MARK: - 菜单面板控制
//
// SwiftUI 没有公开 API 收起 MenuBarExtra 的窗口。这里按社区验证过的做法：
// 找到承载状态栏图标的 NSStatusBarWindow，取出它的 NSStatusItem，
// 再给它自己发一次按钮动作 —— 等同于用户又点了一下图标，窗口就会收起。

enum MenuBarPanel {
    @MainActor
    static func closeIfOpen() {
        for w in NSApp.windows
        where String(describing: type(of: w)).contains("NSStatusBarWindow") {
            guard let item = w.value(forKeyPath: "statusItem") as? NSStatusItem,
                  String(describing: type(of: item)) == "NSStatusItem",
                  let button = item.button,
                  let action = button.action
            else { continue }
            button.sendAction(action, to: button.target)
        }
    }
}

// MARK: - 设置窗口（自管，避免 SwiftUI Window 场景在启动时自动弹出）

enum SettingsWindow {
    private static var retained: NSWindow?

    @MainActor
    static func show(model: AppModel) {
        if let w = retained {
            w.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: SettingsView().environmentObject(model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenAI API 仪表盘设置"
        window.contentView = hosting
        // 关掉后不释放对象：下次直接复用，避免每次重建 SwiftUI 视图树
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        retained = window
    }

    /// 关闭设置窗口（保存后、或用户打开菜单面板时调用）
    @MainActor
    static func close() {
        guard let w = retained else { return }
        w.orderOut(nil)
        w.close()
    }

    @MainActor
    static func closeIfOpen() {
        if let w = retained, w.isVisible { close() }
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
        // 演示模式用假数据，不去碰钥匙串（否则每次重编都要授权）
        _model = StateObject(wrappedValue: demo ? AppModel(demo: true) : AppModel())

        if demo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if CommandLine.arguments.contains("--demo-settings") {
                    DemoWindow.showSettings()
                } else {
                    DemoWindow.show()
                }
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
