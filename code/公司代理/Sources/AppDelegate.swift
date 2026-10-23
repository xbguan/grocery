import Cocoa
import SystemConfiguration

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var timer: Timer?
    private var relay: RelayServer!
    private var controller: ProxyController!
    private var cfg: Config!
    private var settingsWC: SettingsWindowController?
    private var busy = false
    private var uninstalling = false
    private var lastCfgMtime: Date?

    private let statusLine = NSMenuItem(title: "检测中…", action: nil, keyEquivalent: "")
    private let infoLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let autoStartItem = NSMenuItem(title: "开机自动启动", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "启用公司代理", action: nil, keyEquivalent: "")

    // MARK: 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        cfg = Config.load()
        controller = ProxyController(cfg)
        relay = RelayServer(cfg: cfg)
        controller.relayRunning = { [weak self] in self?.relay.isRunning ?? false }
        lastCfgMtime = Self.mtime()

        buildMenu()
        startRelay()
        bootstrapAutoStart()

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        // 首次启动（无配置文件）或显式 --settings 时直接弹出设置
        if CommandLine.arguments.contains("--settings")
            || !FileManager.default.fileExists(atPath: Config.filePath) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.openSettings() }
        }
    }

    private func bootstrapAutoStart() {
        let d = UserDefaults.standard
        if let pref = d.object(forKey: "autostart") as? Bool {
            if pref { _ = LoginItem.enable() } else { LoginItem.disable() }
        } else {
            d.set(true, forKey: "autostart")
            _ = LoginItem.enable()
        }
    }

    private func buildMenu() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        statusLine.isEnabled = false
        infoLine.isEnabled = false

        menu.addItem(statusLine)
        menu.addItem(infoLine)
        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.action = #selector(toggleProxy)
        menu.addItem(toggleItem)
        menu.addItem(make("关闭代理（直连）", #selector(turnOff)))
        menu.addItem(.separator())

        menu.addItem(make("设置…", #selector(openSettings), key: ","))
        menu.addItem(make("测试连接", #selector(quickTest)))
        menu.addItem(make("查看详细状态…", #selector(showStatus)))
        menu.addItem(.separator())

        autoStartItem.target = self
        autoStartItem.action = #selector(toggleAutoStart)
        menu.addItem(autoStartItem)

        menu.addItem(.separator())
        menu.addItem(make("卸载公司代理…", #selector(uninstall)))
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
    }

    private func make(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.target = self
        return mi
    }

    // MARK: 刷新界面

    private func refresh() {
        let (on, addr) = controller.systemProxy()
        let mode = controller.resolvedMode()

        statusLine.title = on ? "● 已启用  \(addr)" : "○ 已关闭（直连）"
        toggleItem.title = on ? "重新应用代理" : "启用公司代理"

        let tunnel: String
        switch mode {
        case .hdvpn: tunnel = "HD-VPN \(controller.ppp0Up() ? "在线" : "断开")"
        case .l2tp:  tunnel = "L2TP 路由"
        case .auto:  tunnel = "自动"
        }
        infoLine.title = "\(controller.primaryIface()) · \(tunnel) · 中继 \(relay.isRunning ? "✓" : "✗") · 自启 \(LoginItem.isEnabled ? "✓" : "✗")"

        let symbol = on ? "building.2.fill" : "building.2"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "公司代理")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.alphaValue = on ? 1.0 : 0.42
        item.button?.toolTip = on
            ? "公司代理：已启用 \(addr)（\(mode.shortTitle)）"
            : "公司代理：已关闭"

        autoStartItem.state = LoginItem.isEnabled ? .on : .off

        if !relay.isRunning {
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.startRelay() }
        }

        // 配置文件被外部（命令行）改动时自动重载
        if let m = Self.mtime(), let last = lastCfgMtime, m > last.addingTimeInterval(0.5) {
            lastCfgMtime = m
            let fresh = Config.load()
            if fresh.host != cfg.host || fresh.port != cfg.port || fresh.user != cfg.user
                || fresh.pass != cfg.pass || fresh.relayPort != cfg.relayPort
                || fresh.vpnMode != cfg.vpnMode || fresh.bypass != cfg.bypass {
                cfg = fresh
                controller.cfg = fresh
                restartRelay()
            }
        }
    }

    private static func mtime() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Config.filePath))?[.modificationDate] as? Date
    }

    // MARK: 中继

    private func startRelay() {
        guard !uninstalling, !relay.isRunning else { return }
        relay.update(cfg: cfg)
        do {
            try relay.start()
            NSLog("corp-proxy: relay listening on %@:%d", cfg.relayHost, cfg.relayPort)
        } catch {
            NSLog("corp-proxy: relay start failed - %@", error.localizedDescription)
        }
    }

    private func restartRelay() {
        relay.stop()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.relay.update(cfg: self.cfg)
            do { try self.relay.start() } catch {
                NSLog("corp-proxy: relay restart failed - %@", error.localizedDescription)
            }
            DispatchQueue.main.async { self.refresh() }
        }
    }

    // MARK: 动作

    private func runAsync(_ work: @escaping () -> (String, Bool), done: @escaping (String, Bool) -> Void) {
        guard !busy else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let (text, ok) = work()
            DispatchQueue.main.async {
                self.busy = false
                self.refresh()
                done(text, ok)
            }
        }
    }

    @objc private func toggleProxy() {
        startRelay()
        runAsync({ [unowned self] in
            switch self.controller.turnOn() {
            case .success(let s): return (s, true)
            case .failure(let f): return (f.message, false)
            }
        }, done: { text, ok in self.show(ok ? "已启用公司代理" : "启用失败", text) })
    }

    @objc private func turnOff() {
        runAsync({ [unowned self] in
            switch self.controller.turnOff() {
            case .success(let s): return (s, true)
            case .failure(let f): return (f.message, false)
            }
        }, done: { text, ok in self.show(ok ? "已关闭代理" : "操作失败", text) })
    }

    @objc private func quickTest() {
        let viaRelay = relay.isRunning
        let proxy = viaRelay ? cfg.relayURL : cfg.upstreamURLWithAuth
        runAsync({ [unowned self] in
            guard Shell.tcpAlive(self.cfg.host, UInt16(self.cfg.port), timeout: 3) else {
                return ("✗ 连不上 \(self.cfg.host):\(self.cfg.port)\n\n\(self.controller.resolvedMode() == .l2tp ? "请确认路由器 L2TP 已接通。" : "请确认 HD-VPN 已连接。")", false)
            }
            let t0 = Date()
            let (_, code) = Shell.run("/usr/bin/curl",
                ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "15",
                 "-x", proxy, "https://chatgpt.com/backend-api/me"], timeout: 20)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let v = code.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = "代理：\(self.cfg.host):\(self.cfg.port)（\(viaRelay ? "经本地中继" : "直连")）\n耗时：\(ms) ms\n\n"
            if v == "401" { return (head + "✓ 出口正常：chatgpt.com → 401", true) }
            if v.isEmpty || v == "000" { return (head + "✗ 访问 chatgpt.com 失败（超时 / 被重置）", false) }
            return (head + "· chatgpt.com → HTTP \(v)", true)
        }, done: { text, ok in self.show(ok ? "连接测试通过" : "连接测试未通过", text) })
    }

    @objc private func showStatus() {
        let text = controller.statusText()
        show("代理状态", text)
    }

    @objc private func toggleAutoStart() {
        if LoginItem.isEnabled {
            LoginItem.disable()
            UserDefaults.standard.set(false, forKey: "autostart")
        } else {
            let ok = LoginItem.enable()
            UserDefaults.standard.set(ok, forKey: "autostart")
            if !ok { show("设置失败", "无法注册开机自启，请到「系统设置 → 通用 → 登录项与扩展」手动添加本 App。") }
        }
        refresh()
    }

    @objc private func openSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController(cfg: cfg) { [weak self] newCfg in
                self?.apply(newCfg)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWC?.showWindow(nil)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
    }

    private func apply(_ newCfg: Config) {
        let wasOn = controller.systemProxy().on
        do {
            try newCfg.save()
        } catch {
            show("保存失败", error.localizedDescription)
            return
        }
        cfg = newCfg
        controller.cfg = newCfg
        lastCfgMtime = Self.mtime()
        restartRelay()

        guard wasOn else {
            refresh()
            return
        }
        runAsync({ [unowned self] in
            switch self.controller.turnOn() {
            case .success(let s): return ("配置已保存并重新应用。\n\n" + s, true)
            case .failure(let f): return (f.message, false)
            }
        }, done: { text, ok in self.show(ok ? "设置已生效" : "已保存，但应用失败", text) })
    }

    // MARK: 卸载

    @objc private func uninstall() {
        if Uninstaller.isTranslocated {
            show("请先安装到「应用程序」", "当前 App 直接从 DMG 里运行（处于隔离路径），无法自删。\n请先把「公司代理」拖到「应用程序」文件夹，再执行卸载。")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "卸载公司代理？"
        a.informativeText = """
        将执行：
        · 关闭系统代理，恢复直连
        · 把 Codex 的 ~/.codex/.env 改回直连
        · 停止本地中继、注销开机自启
        · 删除配置、日志、偏好、缓存与 LaunchAgent
        · 删除 App 本体
        """
        a.alertStyle = .warning
        let cb = NSButton(checkboxWithTitle: "同时删除旧版命令行脚本（~/.local/bin/corp-proxy*）", target: nil, action: nil)
        cb.state = .on
        cb.frame = NSRect(x: 0, y: 0, width: 380, height: 20)
        a.accessoryView = cb
        a.addButton(withTitle: "卸载")
        a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let includeLegacy = cb.state == .on
        uninstalling = true
        if let t = timer { t.invalidate(); timer = nil }
        var progressWindow: NSWindow?
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 96),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "正在卸载…"
        w.center()
        let lab = NSTextField(wrappingLabelWithString: "正在清理…")
        lab.frame = NSRect(x: 20, y: 30, width: 340, height: 40)
        w.contentView?.addSubview(lab)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        progressWindow = w

        Uninstaller.perform(controller: controller, relay: relay, includeLegacy: includeLegacy,
                            progress: { step in lab.stringValue = step },
                            done: { summary in
            progressWindow?.orderOut(nil)
            let fin = NSAlert()
            fin.messageText = "卸载完成"
            fin.informativeText = summary
            fin.addButton(withTitle: "好")
            fin.runModal()
            UserDefaults.standard.removeObject(forKey: "autostart")
            NSApp.terminate(nil)
        })
    }

    // MARK: 弹窗

    private func show(_ title: String, _ body: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body.isEmpty ? "（无输出）" : body
        a.alertStyle = .informational
        a.addButton(withTitle: "好")
        a.runModal()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controller.systemProxy().on else { return .terminateNow }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "系统代理仍然开启"
        a.informativeText = "代理指向本机中继 \(cfg.relayHost):\(cfg.relayPort)，退出 App 后中继会停止，浏览器将无法上网。"
        a.addButton(withTitle: "关闭代理并退出")
        a.addButton(withTitle: "保持开启，仅退出")
        a.addButton(withTitle: "取消")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            _ = controller.turnOff()
            relay.stop()
            return .terminateNow
        case .alertSecondButtonReturn:
            relay.stop()
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
