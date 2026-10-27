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
    /// 启动自检的结论（在菜单信息行里显示一段时间）
    private var note: String?
    private var noteAt: Date?

    private let statusLine = NSMenuItem(title: "检测中…", action: nil, keyEquivalent: "")
    private let infoLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let autoStartItem = NSMenuItem(title: "开机自动启动", action: nil, keyEquivalent: "")
    private let dockItem = NSMenuItem(title: "在程序坞显示", action: nil, keyEquivalent: "")
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
        applyDockVisibility(activate: false)

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        // 首次启动（无配置文件）或显式 --settings 时直接弹出设置
        if CommandLine.arguments.contains("--settings")
            || !FileManager.default.fileExists(atPath: Config.filePath) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.openSettings() }
        }

        // 等中继起来后做一次自检：清理/修正上次遗留的半死状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.startupSelfCheck() }
    }

    /// 启动自检，只处理「我们自己写进去的」代理设置，其它代理（如 Clash）不碰。
    private func startupSelfCheck() {
        let st = controller.systemProxy()
        guard st.on else { return }
        let mine = ["\(cfg.relayHost):\(cfg.relayPort)", "\(cfg.host):\(cfg.port)"]
        guard mine.contains(st.address) else { return }

        // 没有凭据却挂着代理：必然 407 → 浏览器弹认证框，直接关掉
        if !cfg.hasCredentials {
            _ = controller.turnOff()
            setNote("已关闭遗留的系统代理：还没填代理密码")
            refresh()
            return
        }

        // 指向公司上游（直连）而非本地中继：Chromium 不读系统凭据，会弹认证框 → 改为经中继
        if st.address == "\(cfg.host):\(cfg.port)" {
            guard ensureRelayReady() else { return }
            if case .success = controller.turnOn() {
                setNote("已把「直连上游」改为经本地中继（直连会弹代理认证框）")
            }
            refresh()
        }
    }

    private func setNote(_ text: String) {
        note = text
        noteAt = Date()
        NSLog("corp-proxy: %@", text)
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
        menu.addItem(make("关闭代理（直连）", #selector(turnOff), icon: "bolt.slash.fill"))
        menu.addItem(.separator())

        menu.addItem(make("设置…", #selector(openSettings), key: ",", icon: "gearshape"))
        menu.addItem(make("测试连接", #selector(quickTest), icon: "dot.radiowaves.left.and.right"))
        menu.addItem(make("查看详细状态…", #selector(showStatus), icon: "list.bullet.rectangle"))
        menu.addItem(.separator())

        autoStartItem.target = self
        autoStartItem.action = #selector(toggleAutoStart)
        autoStartItem.image = UIStatus.menuImage("power")
        menu.addItem(autoStartItem)

        dockItem.target = self
        dockItem.action = #selector(toggleDockIcon)
        dockItem.image = UIStatus.menuImage("dock.rectangle")
        menu.addItem(dockItem)

        menu.addItem(.separator())
        menu.addItem(make("卸载公司代理…", #selector(uninstall), icon: "trash"))
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = UIStatus.menuImage("rectangle.portrait.and.arrow.right")
        menu.addItem(quit)

        item.menu = menu
    }

    private func make(_ title: String, _ sel: Selector, key: String = "", icon: String? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.target = self
        if let icon { mi.image = UIStatus.menuImage(icon) }
        return mi
    }

    // MARK: 刷新界面

    private func refresh() {
        let (on, addr) = controller.systemProxy()
        let mode = controller.resolvedMode()
        // 顶部表头：图标走菜单项 image（与下方图标列对齐），文字分「状态 / 详情」两列
        let headFont = NSFont.menuFont(ofSize: 0)
        let subFont = NSFont.systemFont(ofSize: 11.5)
        let directUpstream = on && addr == "\(cfg.host):\(cfg.port)"
        if on && directUpstream {
            statusLine.image = UIStatus.image("exclamationmark.triangle.fill", color: .systemOrange, size: 11)
            statusLine.attributedTitle = UIStatus.statusHead(
                state: "已启用", detail: "\(addr)（直连上游，会弹认证框）", font: headFont)
        } else if on {
            statusLine.image = UIStatus.image("circle.fill", color: .systemGreen, size: 9)
            statusLine.attributedTitle = UIStatus.statusHead(
                state: "已启用", detail: addr, font: headFont)
        } else {
            statusLine.image = UIStatus.image("circle", color: .secondaryLabelColor, size: 9)
            statusLine.attributedTitle = UIStatus.statusHead(
                state: "已关闭", detail: cfg.hasCredentials ? "直连" : "未填代理账号", font: headFont)
        }
        infoLine.image = UIStatus.blankIcon
        toggleItem.title = on ? "重新应用代理" : "启用公司代理"
        toggleItem.image = UIStatus.menuImage(on ? "arrow.triangle.2.circlepath" : "bolt.fill")

        let tunnel: String
        switch mode {
        case .hdvpn: tunnel = "HD-VPN \(controller.ppp0Up() ? "在线" : "断开")"
        case .l2tp:  tunnel = "L2TP 路由"
        case .auto:  tunnel = "自动"
        }

        var sub: [UIStatus.Piece] = [.text("\(controller.primaryIface()) · \(tunnel)")]
        sub.append(.text("    "))
        sub.append(.tinted(relay.isRunning ? "bolt.horizontal.fill" : "bolt.slash.fill",
                           relay.isRunning ? .systemGreen : .systemOrange))
        sub.append(.text(" 中继"))
        sub.append(.text("    "))
        sub.append(.tinted("power",
                           LoginItem.isEnabled ? .systemGreen : .secondaryLabelColor))
        sub.append(.text(" 自启"))
        if let n = note, let t = noteAt, Date().timeIntervalSince(t) < 180 {
            sub.append(.text("    ⓘ \(n)"))
        }
        infoLine.attributedTitle = UIStatus.subLine(sub, font: subFont, iconSize: 10)

        let symbol = on ? "building.2.fill" : "building.2"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "公司代理")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.alphaValue = on ? 1.0 : 0.42
        item.button?.toolTip = on
            ? "公司代理：已启用 \(addr)（\(mode.shortTitle)）"
            : "公司代理：已关闭"

        autoStartItem.state = LoginItem.isEnabled ? .on : .off
        dockItem.state = cfg.showInDock ? .on : .off

        if !relay.isRunning {
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.startRelay() }
        }

        // 配置文件被外部（命令行 / 手工）改动时自动重载。
        // 注意 lastCfgMtime 可能是 nil（首次启动时还没有配置文件），
        // 这种情况一旦文件出现就必须重载，否则 App 会一直用默认空配置跑。
        if let m = Self.mtime(), m > (lastCfgMtime ?? .distantPast).addingTimeInterval(0.5) {
            lastCfgMtime = m
            let fresh = Config.load()
            if fresh.host != cfg.host || fresh.port != cfg.port || fresh.user != cfg.user
                || fresh.pass != cfg.pass || fresh.relayPort != cfg.relayPort
                || fresh.vpnMode != cfg.vpnMode || fresh.bypass != cfg.bypass || fresh.showInDock != cfg.showInDock {
                let dockChanged = fresh.showInDock != cfg.showInDock
                cfg = fresh
                controller.cfg = fresh
                if dockChanged { applyDockVisibility(activate: false) }
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

    /// 确保本地中继真的在监听（不只是 isRunning 标志），最多等 timeout 秒
    @discardableResult
    private func ensureRelayReady(timeout: TimeInterval = 3) -> Bool {
        if Shell.tcpAlive(cfg.relayHost, UInt16(cfg.relayPort), timeout: 0.4) { return true }
        startRelay()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Shell.tcpAlive(cfg.relayHost, UInt16(cfg.relayPort), timeout: 0.3) { return true }
            usleep(150_000)
        }
        return false
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
        // 没填账号密码就挂代理，公司 3proxy 会回 407，浏览器会不停弹认证框 —— 先问一句
        var allowEmpty = false
        if !cfg.hasCredentials {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "还没有填写代理账号/密码"
            a.informativeText = """
            公司 3proxy 需要认证。空凭据启用后，浏览器会反复弹出「输入代理用户名和密码」。

            建议先到「设置…」里填写，再启用。
            """
            a.alertStyle = .warning
            a.addButton(withTitle: "去设置…")
            a.addButton(withTitle: "仍然启用")
            a.addButton(withTitle: "取消")
            switch a.runModal() {
            case .alertFirstButtonReturn: openSettings(); return
            case .alertSecondButtonReturn: allowEmpty = true
            default: return
            }
        }

        runAsync({ [unowned self] in
            guard self.ensureRelayReady() else {
                return ("本地中继没起来（\(self.cfg.relayHost):\(self.cfg.relayPort)）\n\n本次没有改动系统代理。请稍后重试，或重启 App；若端口被占用，可在设置里换一个中继端口。", false)
            }
            switch self.controller.turnOn(allowEmptyCredentials: allowEmpty) {
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
                return ("连不上 \(self.cfg.host):\(self.cfg.port)\n\n\(self.controller.resolvedMode() == .l2tp ? "请确认路由器 L2TP 已接通。" : "请确认 HD-VPN 已连接。")", false)
            }
            let t0 = Date()
            let (_, code) = Shell.run("/usr/bin/curl",
                ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "15",
                 "-x", proxy, "https://chatgpt.com/backend-api/me"], timeout: 20)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let v = code.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = "代理：\(self.cfg.host):\(self.cfg.port)（\(viaRelay ? "经本地中继" : "直连")）\n耗时：\(ms) ms\n\n"
            if v == "401" { return (head + "出口正常：chatgpt.com → 401", true) }
            if v.isEmpty || v == "000" { return (head + "访问 chatgpt.com 失败（超时 / 被重置）", false) }
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

    // MARK: 程序坞

    /// regular = 有 Dock 图标 + 菜单栏菜单；accessory = 仅菜单栏常驻
    private func applyDockVisibility(activate: Bool) {
        if cfg.showInDock {
            NSApp.setActivationPolicy(.regular)
            installMainMenu()
            if activate { NSApp.activate(ignoringOtherApps: true) }
        } else {
            NSApp.setActivationPolicy(.accessory)
            NSApp.mainMenu = nil
        }
        dockItem.state = cfg.showInDock ? .on : .off
    }

    @objc private func toggleDockIcon() {
        cfg.showInDock.toggle()
        do {
            try cfg.save()
        } catch {
            cfg.showInDock.toggle()
            show("保存失败", error.localizedDescription)
            return
        }
        controller.cfg = cfg
        lastCfgMtime = Self.mtime()
        applyDockVisibility(activate: cfg.showInDock)
        refresh()
    }

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appSub = NSMenu()
        appItem.submenu = appSub
        main.addItem(appItem)
        appSub.addItem(mi("关于公司代理", #selector(showAbout)))
        appSub.addItem(.separator())
        appSub.addItem(mi("设置…", #selector(openSettings), key: ","))
        appSub.addItem(.separator())
        appSub.addItem(NSMenuItem(title: "隐藏公司代理", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appSub.addItem(.separator())
        appSub.addItem(NSMenuItem(title: "退出公司代理", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let proxyItem = NSMenuItem()
        let proxySub = NSMenu(title: "代理")
        proxyItem.submenu = proxySub
        main.addItem(proxyItem)
        let on = controller.systemProxy().on
        proxySub.addItem(mi(on ? "重新应用代理" : "启用公司代理", #selector(toggleProxy),
                            icon: on ? "arrow.triangle.2.circlepath" : "bolt.fill"))
        proxySub.addItem(mi("关闭代理（直连）", #selector(turnOff), icon: "bolt.slash.fill"))
        proxySub.addItem(.separator())
        proxySub.addItem(mi("测试连接", #selector(quickTest), icon: "dot.radiowaves.left.and.right"))
        proxySub.addItem(mi("查看详细状态…", #selector(showStatus), icon: "list.bullet.rectangle"))

        let winItem = NSMenuItem()
        let winSub = NSMenu(title: "窗口")
        winItem.submenu = winSub
        main.addItem(winItem)
        winSub.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        winSub.addItem(NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        NSApp.mainMenu = main
    }

    private func mi(_ title: String, _ sel: Selector, key: String = "", icon: String? = nil) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        m.target = self
        if let icon { m.image = UIStatus.menuImage(icon) }
        return m
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let credits = NSAttributedString(
            string: "公司 3proxy 一键开关 · 本地免认证中继",
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "公司代理",
            .applicationVersion: version,
            .credits: credits,
        ])
    }

    // 点 Dock 图标：不弹设置窗口，改成和点顶部菜单栏图标一样把菜单弹出来
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }        // 设置窗口已开着：交给系统前置即可
        DispatchQueue.main.async { [weak self] in self?.popUpStatusMenu() }
        return false
    }

    /// 以菜单栏图标为锚点弹出主菜单（与鼠标直接点图标视觉一致）
    private func popUpStatusMenu() {
        guard let button = item.button, let menu = item.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }

    // 右键 Dock 图标
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        let on = controller.systemProxy().on
        m.addItem(mi(on ? "重新应用代理" : "启用公司代理", #selector(toggleProxy),
                     icon: on ? "arrow.triangle.2.circlepath" : "bolt.fill"))
        if on { m.addItem(mi("关闭代理（直连）", #selector(turnOff), icon: "bolt.slash.fill")) }
        m.addItem(.separator())
        m.addItem(mi("设置…", #selector(openSettings), icon: "gearshape"))
        return m
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
        let dockChanged = newCfg.showInDock != cfg.showInDock
        do {
            try newCfg.save()
        } catch {
            show("保存失败", error.localizedDescription)
            return
        }
        cfg = newCfg
        controller.cfg = newCfg
        lastCfgMtime = Self.mtime()
        if dockChanged { applyDockVisibility(activate: newCfg.showInDock) }
        restartRelay()

        guard wasOn else {
            refresh()
            return
        }

        // 密码被清空却还在启用状态：直接关掉，否则公司代理回 407，浏览器会弹认证框
        if !newCfg.hasCredentials {
            _ = controller.turnOff()
            refresh()
            show("已自动关闭代理", "代理账号/密码为空，已关闭系统代理，避免浏览器反复弹出认证框。\n填好账号密码后再点「启用公司代理」即可。")
            return
        }

        runAsync({ [unowned self] in
            guard self.ensureRelayReady() else {
                return ("配置已保存，但本地中继没起来，未重新挂载系统代理。\n请检查中继端口 \(self.cfg.relayPort) 是否被占用。", false)
            }
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
