import Cocoa

// MARK: - 密码框（可切换可见）

final class SecretField: NSView {
    private let secure = NSSecureTextField()
    private let plain = NSTextField()
    private(set) var revealed = false

    var stringValue: String {
        get { revealed ? plain.stringValue : secure.stringValue }
        set { secure.stringValue = newValue; plain.stringValue = newValue }
    }

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        for f in [secure, plain] as [NSTextField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.font = .systemFont(ofSize: 13)
            f.placeholderString = "公司代理密码"
            addSubview(f)
            NSLayoutConstraint.activate([
                f.leadingAnchor.constraint(equalTo: leadingAnchor),
                f.trailingAnchor.constraint(equalTo: trailingAnchor),
                f.topAnchor.constraint(equalTo: topAnchor),
                f.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        plain.isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func toggle() {
        let v = stringValue
        revealed.toggle()
        secure.isHidden = revealed
        plain.isHidden = !revealed
        stringValue = v
        window?.makeFirstResponder(revealed ? plain : secure)
    }
}

// MARK: - 设置窗口

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {

    private var cfg: Config
    private let onSave: (Config) -> Void

    private let hostField = NSTextField()
    private let portField = NSTextField()
    private let userField = NSTextField()
    private let passField = SecretField(width: 210)
    private let relayPortField = NSTextField()
    private let bypassField = NSTextField()
    private let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modeHint = NSTextField(labelWithString: "")
    private let dockCheck = NSButton(checkboxWithTitle: "在程序坞显示图标", target: nil, action: nil)
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private let testButton = NSButton(title: "测试连接", target: nil, action: nil)

    init(cfg: Config, onSave: @escaping (Config) -> Void) {
        self.cfg = cfg
        self.onSave = onSave
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "公司代理 · 设置"
        win.isReleasedWhenClosed = false
        win.center()
        super.init(window: win)
        build()
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 构建界面

    private func label(_ text: String, width: CGFloat = 84) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        l.font = .systemFont(ofSize: 13)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: width).isActive = true
        return l
    }

    private func field(_ f: NSTextField, width: CGFloat) {
        f.font = .systemFont(ofSize: 13)
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        f.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    private func section(_ title: String) -> NSStackView {
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 11, weight: .semibold)
        t.textColor = .secondaryLabelColor
        let s = NSStackView(views: [t])
        s.orientation = .horizontal
        return s
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 8
        s.alignment = .centerY
        return s
    }

    private func spacer(_ width: CGFloat = 0, h: CGFloat = 0) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        if width > 0 { v.widthAnchor.constraint(equalToConstant: width).isActive = true }
        if h > 0 { v.heightAnchor.constraint(equalToConstant: h).isActive = true }
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    private func dimLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func build() {
        guard let content = window?.contentView else { return }

        hostField.placeholderString = "172.17.2.15 或域名"
        portField.placeholderString = "7887"
        userField.placeholderString = "admin"
        relayPortField.placeholderString = "7899"
        bypassField.placeholderString = "空格分隔，如 *.hd123.com"

        field(hostField, width: 200)
        field(portField, width: 80)
        field(userField, width: 200)
        field(relayPortField, width: 80)
        field(bypassField, width: 470)
        bypassField.font = .systemFont(ofSize: 11)

        modePopup.removeAllItems()
        for m in VPNMode.allCases { modePopup.addItem(withTitle: m.title) }
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        modePopup.widthAnchor.constraint(equalToConstant: 280).isActive = true

        modeHint.font = .systemFont(ofSize: 11)
        modeHint.textColor = .secondaryLabelColor
        modeHint.preferredMaxLayoutWidth = 440
        modeHint.lineBreakMode = .byWordWrapping
        modeHint.maximumNumberOfLines = 2

        dockCheck.font = .systemFont(ofSize: 12)
        dockCheck.translatesAutoresizingMaskIntoConstraints = false

        let reveal = NSButton(checkboxWithTitle: "显示", target: self, action: #selector(toggleReveal))
        reveal.font = .systemFont(ofSize: 11)
        reveal.translatesAutoresizingMaskIntoConstraints = false

        resultLabel.font = .systemFont(ofSize: 11)
        resultLabel.textColor = .secondaryLabelColor
        resultLabel.alignment = .left
        resultLabel.preferredMaxLayoutWidth = 470
        resultLabel.stringValue = ""

        testButton.target = self
        testButton.action = #selector(runTest)
        testButton.bezelStyle = .rounded
        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let save = NSButton(title: "保存并应用", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.translatesAutoresizingMaskIntoConstraints = false
        save.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.widthAnchor.constraint(equalToConstant: 78).isActive = true

        let buttons = NSStackView(views: [testButton, spacer(), cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let note = NSTextField(wrappingLabelWithString:
            "保存后会立即重启本地中继，并按新参数重新挂载系统代理。菜单栏「卸载公司代理…」可连同配置、日志、开机自启一并清除。")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.preferredMaxLayoutWidth = 540

        // 说明文字缩进到与输入框对齐
        let hintRow = row([spacer(92), modeHint])

        let stack = NSStackView(views: [
            section("公司 3proxy 代理"),
            row([label("代理地址"), hostField, label("端口", width: 40), portField]),
            row([label("用户名"), userField, label("密码", width: 40), passField, reveal]),
            section("VPN 接入方式"),
            row([label("方式"), modePopup]),
            hintRow,
            section("本地中继（浏览器免认证）"),
            row([label("端口"), relayPortField, dimLabel("系统代理指向 127.0.0.1:该端口，由 App 代填认证")]),
            section("直连白名单"),
            row([label("不走代理"), bypassField]),
            section("外观"),
            row([spacer(92), dockCheck, dimLabel("勾选后可常驻程序坞，右键图标可快速开关代理")]),
            spacer(h: 8),
            resultLabel,
            buttons,
            note,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
        ])
    }

    // MARK: 数据绑定

    private func load() {
        hostField.stringValue = cfg.host
        portField.stringValue = String(cfg.port)
        userField.stringValue = cfg.user
        passField.stringValue = cfg.pass
        relayPortField.stringValue = String(cfg.relayPort)
        bypassField.stringValue = cfg.bypass
        modePopup.selectItem(at: VPNMode.allCases.firstIndex(of: cfg.vpnMode) ?? 0)
        dockCheck.state = cfg.showInDock ? .on : .off
        updateModeHint()
    }

    @objc private func modeChanged() { updateModeHint() }

    private func updateModeHint() {
        let m = VPNMode.allCases[max(0, modePopup.indexOfSelectedItem)]
        switch m {
        case .auto:
            modeHint.stringValue = "检测 ppp0 有无地址：有则按 HD-VPN，否则按路由器 L2TP"
        case .hdvpn:
            modeHint.stringValue = "本机拨号：系统代理会同时挂到「VPN」服务"
        case .l2tp:
            modeHint.stringValue = "路由器拨号：只挂物理网卡，不设置 VPN 服务"
        }
    }

    @objc private func toggleReveal() { passField.toggle() }

    private func collect() -> Config? {
        var c = cfg
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { bad("代理地址不能为空"); return nil }
        guard let port = Int(portField.stringValue.trimmingCharacters(in: .whitespaces)), (1...65535).contains(port) else {
            bad("代理端口需为 1–65535"); return nil
        }
        guard let rport = Int(relayPortField.stringValue.trimmingCharacters(in: .whitespaces)), (1024...65535).contains(rport) else {
            bad("中继端口需为 1024–65535"); return nil
        }
        c.host = host
        c.port = port
        c.user = userField.stringValue.trimmingCharacters(in: .whitespaces)
        c.pass = passField.stringValue
        c.relayPort = rport
        c.bypass = bypassField.stringValue.trimmingCharacters(in: .whitespaces)
        c.vpnMode = VPNMode.allCases[max(0, modePopup.indexOfSelectedItem)]
        c.showInDock = dockCheck.state == .on
        return c
    }

    private func bad(_ msg: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "参数不合法"
        a.informativeText = msg
        a.alertStyle = .warning
        a.addButton(withTitle: "好")
        a.runModal()
    }

    @objc private func save() {
        guard let c = collect() else { return }
        onSave(c)
        close()
    }

    @objc private func cancel() { close() }

    @objc private func runTest() {
        guard let c = collect() else { return }
        testButton.isEnabled = false
        resultLabel.stringValue = "正在测试 \(c.host):\(c.port) …"
        resultLabel.textColor = .secondaryLabelColor

        DispatchQueue.global(qos: .userInitiated).async {
            let reachable = Shell.tcpAlive(c.host, UInt16(c.port), timeout: 3)
            var rows: [(String, NSColor, String)] = []
            if reachable {
                rows.append(("circle.fill", .systemGreen, "代理端口 \(c.host):\(c.port) 可连接"))
            } else {
                rows.append(("exclamationmark.triangle.fill", .systemOrange,
                             "代理端口不可达（VPN 是否已连接？若为路由器 L2TP，请确认内网路由）"))
            }
            if reachable {
                let t0 = Date()
                let (_, code) = Shell.run("/usr/bin/curl",
                    ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "15",
                     "-x", c.upstreamURLWithAuth, "https://chatgpt.com/backend-api/me"], timeout: 20)
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let v = code.trimmingCharacters(in: .whitespacesAndNewlines)
                if v == "401" {
                    rows.append(("bolt.horizontal.fill", .systemGreen,
                                 "出口正常 chatgpt.com → 401（\(ms) ms）"))
                } else if v.isEmpty || v == "000" {
                    rows.append(("exclamationmark.triangle.fill", .systemOrange,
                                 "通过代理访问 chatgpt.com 失败（超时或被重置）"))
                } else {
                    rows.append(("dot.radiowaves.left.and.right", .secondaryLabelColor,
                                 "通过代理访问 chatgpt.com → HTTP \(v)（\(ms) ms）"))
                }
            }
            let att = Self.testResult(rows)
            DispatchQueue.main.async {
                self.resultLabel.attributedStringValue = att
                self.testButton.isEnabled = true
            }
        }
    }

    /// 测试结果里「图标 + 文字」的组装，替代原来的 ✓ / ✗ 字符
    private static func testResult(_ rows: [(String, NSColor, String)]) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11)
        let out = NSMutableAttributedString()
        for (i, r) in rows.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(UIStatus.inline(r.0, color: r.1, font: font))
            out.append(NSAttributedString(string: " " + r.2, attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return out
    }
}
