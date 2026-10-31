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

    /// 退出清理是否已执行（保证只跑一次）
    private var exitCleanupDone = false
    /// 系统正在关机 / 重启 / 注销
    private var poweringOff = false
    /// 串行化退出清理：主线程的 terminate 与信号线程不会同时进来
    private let exitQueue = DispatchQueue(label: "local.xbguan.corpproxy.exit")
    /// 信号源要保活，否则会被释放掉
    private var signalSources: [DispatchSourceSignal] = []

    /// 主菜单是自绘的玻璃浮层（系统 NSMenu 的外观无法改）
    private let menuPanel = MenuPanelController()
    /// 上次送进面板的内容签名，避免定时刷新时无谓重建
    private var menuVersion = ""

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
        installExitHandlers()

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
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        guard let button = item.button else { return }
        let anchor = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
        menuPanel.toggle(anchor: anchor, model: buildMenuModel())
    }

    /// 组装菜单内容。每次都重新读状态：面板开着时定时刷新也能反映最新值。
    private func buildMenuModel() -> MenuModel {
        let (on, addr) = controller.systemProxy()
        let mode = controller.resolvedMode()
        let directUpstream = on && addr == "\(cfg.host):\(cfg.port)"

        var title = "已关闭"
        var detail = cfg.hasCredentials ? "直连" : "未填代理账号"
        var warn = false
        if on && directUpstream {
            title = "已启用"
            detail = "\(addr) · 直连上游"
            warn = true
        } else if on {
            title = "已启用"
            detail = addr
        }

        let tunnel: String
        switch mode {
        case .hdvpn: tunnel = "HD-VPN \(controller.ppp0Up() ? "在线" : "断开")"
        case .l2tp:  tunnel = "路由器 L2TP"
        case .auto:  tunnel = "自动选择"
        }
        let tunnelOK = (mode == .l2tp) || controller.ppp0Up()

        let pills = [
            MenuPill(icon: "network", text: "\(controller.primaryIface()) · \(tunnel)",
                     tint: tunnelOK ? .systemGreen : .systemOrange),
            MenuPill(icon: relay.isRunning ? "bolt.horizontal.fill" : "bolt.slash.fill",
                     text: "中继", tint: relay.isRunning ? .systemGreen : .systemOrange),
            MenuPill(icon: "power", text: "自启",
                     tint: LoginItem.isEnabled ? .systemGreen : .tertiaryLabelColor),
        ]
        let freshNote: String? = {
            guard let n = note, let t = noteAt,
                  Date().timeIntervalSince(t) < 180 else { return nil }
            return n
        }()

        let header = MenuHeader(on: on, title: title, detail: detail,
                                pills: pills, note: freshNote, warn: warn)

        let normal = MenuTheme.normalTint

        let toggle = MenuEntry(
            id: on ? "reapply" : "turnon",
            title: on ? "重新应用代理" : "启用公司代理",
            icon: on ? "arrow.triangle.2.circlepath" : "bolt.fill",
            tint: .controlAccentColor) { [weak self] in
                guard let self else { return }
                self.menuPanel.hide()
                self.toggleProxy()
            }

        var off = MenuEntry(id: "turnoff", title: "关闭代理（直连）",
                            icon: "bolt.slash.fill", tint: .systemOrange) { [weak self] in
            guard let self else { return }
            self.menuPanel.hide()
            self.turnOff()
        }
        off.enabled = on

        let settings = MenuEntry(id: "settings", title: "设置…", icon: "gearshape",
                                 tint: normal, key: "⌘,") { [weak self] in
            self?.menuPanel.hide()
            self?.openSettings()
        }
        let test = MenuEntry(id: "test", title: "测试连接",
                             icon: "dot.radiowaves.left.and.right", tint: normal) { [weak self] in
            self?.menuPanel.hide()
            self?.quickTest()
        }
        let status = MenuEntry(id: "status", title: "查看详细状态…",
                               icon: "list.bullet.rectangle", tint: normal) { [weak self] in
            self?.menuPanel.hide()
            self?.showStatus()
        }

        let autoStart = MenuEntry(id: "autostart", title: "开机自动启动", icon: "power",
                                  tint: normal, checked: LoginItem.isEnabled) { [weak self] in
            self?.menuPanel.hide()
            self?.toggleAutoStart()
        }
        let autoOff = MenuEntry(id: "autooff", title: "退出时关闭代理",
                                icon: "door.left.hand.open", tint: normal,
                                checked: Self.autoOffOnQuit) { [weak self] in
            self?.menuPanel.hide()
            self?.toggleAutoOffOnQuit()
        }
        let dock = MenuEntry(id: "dock", title: "在程序坞显示", icon: "dock.rectangle",
                             tint: normal, checked: cfg.showInDock) { [weak self] in
            self?.menuPanel.hide()
            self?.toggleDockIcon()
        }

        let uninstall = MenuEntry(id: "uninstall", title: "卸载公司代理…", icon: "trash",
                                  tint: .systemRed) { [weak self] in
            self?.menuPanel.hide()
            self?.uninstall()
        }
        let quit = MenuEntry(id: "quit", title: "退出", icon: "rectangle.portrait.and.arrow.right",
                             tint: normal, key: "⌘Q") { [weak self] in
            self?.menuPanel.hide()
            NSApp.terminate(nil)
        }

        let groups = [[toggle, off], [settings, test, status], [autoStart, autoOff, dock], [uninstall, quit]]

        let version = [
            on ? "1" : "0", addr, title, detail, tunnel, "\(relay.isRunning)", "\(LoginItem.isEnabled)",
            "\(Self.autoOffOnQuit)", "\(cfg.showInDock)", freshNote ?? "",
        ].joined(separator: "|")

        return MenuModel(header: header, groups: groups, version: version)
    }

    // MARK: 刷新界面

    private func refresh() {
        let (on, addr) = controller.systemProxy()
        let mode = controller.resolvedMode()

        let symbol = on ? "building.2.fill" : "building.2"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "公司代理")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.alphaValue = on ? 1.0 : 0.42
        item.button?.toolTip = on
            ? "公司代理：已启用 \(addr)（\(mode.shortTitle)）"
            : "公司代理：已关闭"

        // 面板开着时同步最新状态；内容没变就不重建，避免每 5 秒抖一下
        let model = buildMenuModel()
        if model.version != menuVersion {
            menuVersion = model.version
            if menuPanel.isVisible { menuPanel.update(model) }
        }

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

    /// 同上，但结果是卡片模型，供 InfoCard 渲染
    private func runAsyncCard(_ work: @escaping () -> InfoCardModel,
                              done: @escaping (InfoCardModel) -> Void) {
        guard !busy else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let model = work()
            DispatchQueue.main.async {
                self.busy = false
                self.refresh()
                done(model)
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
        let addr = "\(cfg.host):\(cfg.port)"
        let route = viaRelay
            ? "经本地中继 \(cfg.relayHost):\(cfg.relayPort) 转发"
            : "直连公司代理"
        let hint = controller.resolvedMode() == .l2tp
            ? "确认路由器 L2TP 已接通，本机在公司内网路由上。"
            : "确认 HD-VPN 已连接（ppp0 有地址）。"

        runAsyncCard({ [unowned self] in
            let facts: [InfoFact] = [
                InfoFact("server.rack", "代理 \(addr)"),
                InfoFact("point.topleft.down.to.point.bottomright.curvepath", route),
            ]
            guard Shell.tcpAlive(self.cfg.host, UInt16(self.cfg.port), timeout: 3) else {
                return InfoCardModel(tone: .warn, title: "连不上代理端口",
                                     subtitle: "\(addr) 没有响应",
                                     facts: facts, footnote: hint)
            }
            let t0 = Date()
            let (_, code) = Shell.run("/usr/bin/curl",
                ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "15",
                 "-x", proxy, "https://chatgpt.com/backend-api/me"], timeout: 20)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let v = code.trimmingCharacters(in: .whitespacesAndNewlines)
            let msChip = InfoChip(icon: "clock", tint: .secondaryLabelColor,
                                  value: "\(ms) ms", caption: "耗时")

            switch v {
            case "401":
                return InfoCardModel(
                    tone: .ok, title: "链路正常",
                    subtitle: "请求已到达 chatgpt.com，认证与出口都通",
                    chips: [msChip,
                            InfoChip(icon: "bolt.horizontal", tint: .systemGreen,
                                     value: "401", caption: "chatgpt.com")],
                    facts: facts)
            case "", "000":
                return InfoCardModel(tone: .warn, title: "出口不通",
                                     subtitle: "代理连上了，但 chatgpt.com 没有回应",
                                     chips: [msChip],
                                     facts: facts, footnote: hint)
            default:
                return InfoCardModel(tone: .warn, title: "链路有响应",
                                     subtitle: "返回 HTTP \(v)，不是预期的 401",
                                     chips: [msChip], facts: facts)
            }
        }, done: { InfoCard.present($0) })
    }

    @objc private func showStatus() {
        let on = controller.systemProxy().on
        var kv: [String: String] = [:]
        for sec in controller.statusSections() {
            for (k, v) in sec { kv[k] = v }
        }

        let iface = kv["主接口"] ?? "—"
        let access = kv["接入方式"] ?? "—"
        let tunnel = kv["隧道"] ?? "—"
        let sysProxy = kv["系统代理"] ?? "—"
        let relayInfo = kv["本地中继"] ?? "—"
        let codex = kv["Codex"] ?? "—"
        let upstream = kv["公司代理"] ?? "—"
        let user = kv["用户"] ?? "—"
        let port = kv["中继端口"] ?? "—"

        let bad = ["断开", "不通", "不可达", "已关闭", "未运行", "直连"]
        func healthy(_ s: String) -> Bool { !bad.contains(where: { s.contains($0) }) }

        let tunnelOK = healthy(tunnel)
        let relayOK = healthy(relayInfo)
        let codexOK = healthy(codex)

        let chips = [
            InfoChip(icon: "network", tint: tunnelOK ? .systemGreen : .systemOrange,
                     value: iface, caption: "主接口"),
            InfoChip(icon: "bolt.horizontal.fill", tint: relayOK ? .systemGreen : .systemOrange,
                     value: port, caption: "中继"),
            InfoChip(icon: "list.bullet", tint: .secondaryLabelColor,
                     value: "\(controller.servicesToSet().count)", caption: "网络服务"),
        ]

        let facts = [
            InfoFact("lock.shield", "接入 \(access)", detail: tunnel,
                     tint: tunnelOK ? .systemGreen : .systemOrange),
            InfoFact("globe", "系统代理\(sysProxy)",
                     tint: on ? .systemGreen : .systemOrange),
            InfoFact("arrow.triangle.2.circlepath", "本地中继 \(relayInfo)",
                     tint: relayOK ? .systemGreen : .systemOrange),
            InfoFact("terminal", "Codex \(codex)",
                     tint: codexOK ? .systemGreen : .secondaryLabelColor),
            InfoFact("server.rack", "公司代理 \(upstream)", detail: "账号 \(user)"),
        ]

        InfoCard.present(InfoCardModel(
            tone: on ? .ok : .neutral,
            title: on ? "代理运行中" : "当前直连",
            subtitle: on
                ? (codexOK ? "系统代理与 Codex 都指向公司线路" : "系统代理已启用，Codex 仍为直连")
                : "系统代理未开启，全部走本地网络",
            chips: chips, facts: facts,
            footnote: "覆盖 \(controller.servicesToSet().count) 个网络服务："
                + controller.servicesToSet().joined(separator: "、")))
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
        guard let button = item.button else { return }
        let anchor = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
        menuPanel.show(anchor: anchor, model: buildMenuModel())
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

    // MARK: 退出

    /// 退出时是否自动关闭系统代理（默认开）
    private static var autoOffOnQuit: Bool {
        get { UserDefaults.standard.object(forKey: "autoOffOnQuit") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoOffOnQuit") }
    }

    @objc private func toggleAutoOffOnQuit() {
        Self.autoOffOnQuit = !Self.autoOffOnQuit
        menuVersion = ""
        refresh()
    }

    /// 注册所有能捕获到的退出入口。
    ///
    /// 覆盖范围：
    /// - 菜单「退出」 / ⌘Q / 程序坞右键「退出」 / AppleScript quit → `applicationShouldTerminate`
    /// - 关机 / 重启 / 注销 → `NSWorkspace.willPowerOff` + 随后的 terminate
    /// - `kill` / `killall` / 系统在关机超时后发的 SIGTERM，以及 Ctrl-C → 信号源
    ///
    /// 覆盖不了：SIGKILL（强制退出、崩溃、关机超时被硬杀）。此时进程没有机会执行任何代码，
    /// 只能靠下次启动时的自检把残留的代理设置纠正回来。
    private func installExitHandlers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.poweringOff = true
            // 关机/注销时提前清一次，别等到系统给的几秒宽限期才动手
            self.cleanupBeforeExit(reason: "关机 / 注销")
        }

        let sigQueue = DispatchQueue(label: "local.xbguan.corpproxy.signal")
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)        // 挡掉默认的「立刻杀死进程」
            let src = DispatchSource.makeSignalSource(signal: sig, queue: sigQueue)
            src.setEventHandler { [weak self] in
                self?.cleanupBeforeExit(reason: "signal \(sig)")
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    /// 退出前清理；串行队列保证「多入口并发」时也只会执行一次
    private func cleanupBeforeExit(reason: String) {
        exitQueue.sync {
            guard !exitCleanupDone else { return }
            exitCleanupDone = true
            performExitCleanup(reason: reason)
        }
    }

    private func performExitCleanup(reason: String) {
        guard Self.autoOffOnQuit else {
            NSLog("corp-proxy: 退出（%@），已按设置保留系统代理", reason)
            relay.stop()
            return
        }

        // 不看「global 代理状态」：主服务未必是我们设过代理的那个
        // （例如主服务是 ppp0/VPN 时会话，而代理设在 Wi-Fi 上），
        // 只看每个服务自己的地址，是「我们的」才撤，别家的（Clash 等）不碰。
        let closed = controller.turnOffOwnProxyOnly()
        if closed.isEmpty {
            NSLog("corp-proxy: 退出（%@），没有发现本 App 设置的系统代理", reason)
        } else {
            // 先撤系统代理，再停中继 —— 反过来的话中间会有一段「代理在、中继死」的空窗
            controller.rewriteCodexEnv(enabled: false, viaRelay: false)
            NSLog("corp-proxy: 退出（%@）已关闭系统代理，涉及服务：%@",
                  reason, closed.joined(separator: "、"))
        }

        relay.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if uninstalling { return .terminateNow }    // 卸载流程自己已经清理过
        cleanupBeforeExit(reason: poweringOff ? "关机 / 注销" : "退出")
        return .terminateNow
    }
}
