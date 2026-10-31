import Cocoa

// MARK: - 尺寸与字号
//
// 统一在这里调：整体观感对标 macOS 26/27 的「更大控件 + 更宽松留白」，
// 但不依赖 macOS 26 才有的 Liquid Glass API（本机 14.x 无法使用）。
//
// 列宽口径：所有卡片的行都按同一套列坐标排版 ——
//   标签 96 | 主控件 300 | 小标签 44 | 小控件 124 | 说明 200（共 804）
// 每一行的起点、每一列的分界线在所有卡片里都严格对齐。

enum Metric {
    /// 正文字号
    static let body: CGFloat = 14
    /// 说明/次要文字
    static let small: CGFloat = 12
    /// 区块标题
    static let section: CGFloat = 12
    /// 输入框高度
    static let fieldH: CGFloat = 30
    /// 左侧标签列
    static let labelW: CGFloat = 96
    /// 主控件列（输入框 / 下拉框 / 复选框）
    static let controlW: CGFloat = 300
    /// 行内小标签（端口 / 密码）
    static let miniLabelW: CGFloat = 44
    /// 行内小控件
    static let miniFieldW: CGFloat = 124
    /// 列间距
    static let gap: CGFloat = 10
    /// 主控件 + 小控件占满整段（白名单这种长文本用）
    static var controlSpanW: CGFloat { controlW + gap + miniLabelW + gap + miniFieldW }
    /// 窗口内容宽度
    static let windowW: CGFloat = 880
    /// 卡片内边距
    static let cardPad: CGFloat = 14
    /// 卡片圆角
    static let cardRadius: CGFloat = 10
    /// 窗口左右边距
    static let margin: CGFloat = 24
    /// 行距
    static let rowGap: CGFloat = 10
    /// 卡片之间的空隙
    static let cardGap: CGFloat = 14
    /// 卡片内部可用宽度
    static var cardInnerW: CGFloat { windowW - margin * 2 - cardPad * 2 }
    /// 说明列（吃掉剩余宽度）
    static var noteW: CGFloat { cardInnerW - labelW - gap - controlSpanW - gap }
}

// MARK: - 分组卡片

/// 圆角分组容器：模拟新版系统设置里「一格一格」的分组观感。
final class CardView: NSView {
    init(_ content: NSView, padding: CGFloat = Metric.cardPad) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Metric.cardRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ])
        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            guard let layer = self?.layer else { return }
            layer.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        }
    }
}

// MARK: - 设置窗口

final class SettingsWindowController: NSWindowController {

    private var cfg: Config
    private let onSave: (Config) -> Void

    private let hostBox = FieldBox()
    private let portBox = FieldBox()
    private let userBox = FieldBox()
    private let passBox = PasswordBox()
    private let relayBox = FieldBox()
    private let bypassBox = FieldBox(font: .systemFont(ofSize: Metric.small), lines: 2)
    private let modeField = SelectBox()
    private let dockSwitch = NSSwitch()
    private let testButton = NSButton(title: "测试连接", target: nil, action: nil)

    private let mainStack = NSStackView()
    private let resultHolder = NSStackView()

    init(cfg: Config, onSave: @escaping (Config) -> Void) {
        self.cfg = cfg
        self.onSave = onSave
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Metric.windowW, height: 600),
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

    // MARK: 构件

    private func label(_ text: String, width: CGFloat = Metric.labelW) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        l.font = .systemFont(ofSize: Metric.body)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        l.widthAnchor.constraint(equalToConstant: width).isActive = true
        return l
    }

    private func noteLabel(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: Metric.small)
        l.textColor = .secondaryLabelColor
        l.isSelectable = false
        l.maximumNumberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        l.preferredMaxLayoutWidth = Metric.noteW
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        l.widthAnchor.constraint(equalToConstant: Metric.noteW).isActive = true
        return l
    }

    private func section(_ title: String) -> NSTextField {
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: Metric.section, weight: .semibold)
        t.textColor = .secondaryLabelColor
        t.translatesAutoresizingMaskIntoConstraints = false
        return t
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = Metric.gap
        s.alignment = .centerY
        return s
    }

    private func column(_ views: [NSView], spacing: CGFloat = Metric.rowGap) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .width
        s.spacing = spacing
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

    /// 把控件放进固定宽度的列里：左对齐，输入框类撑满列宽，
    /// 开关这类固定尺寸的控件保持原宽度（否则 NSSwitch 会被拉伸后画在列中央）
    private func columnize(_ control: NSView, width: CGFloat) -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: width).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(control)

        var rules: [NSLayoutConstraint] = [
            control.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            control.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: box.topAnchor),
            control.bottomAnchor.constraint(lessThanOrEqualTo: box.bottomAnchor),
        ]
        if !(control is NSSwitch) && !(control is NSButton) {
            rules.append(control.widthAnchor.constraint(equalTo: box.widthAnchor))
        }
        NSLayoutConstraint.activate(rules)
        return box
    }

    /// 一行表单：所有行列宽固定，说明列吃掉剩余宽度
    private func formRow(_ labelText: String,
                         control: NSView,
                         controlWidth: CGFloat = Metric.controlW,
                         miniLabel: String? = nil,
                         miniControl: NSView? = nil,
                         note: String = "") -> NSStackView {
        var cells: [NSView] = [label(labelText), columnize(control, width: controlWidth)]
        if controlWidth < Metric.controlSpanW {
            cells.append(miniLabel.map { label($0, width: Metric.miniLabelW) } ?? spacer(Metric.miniLabelW))
            if let mc = miniControl {
                cells.append(columnize(mc, width: Metric.miniFieldW))
            } else {
                cells.append(spacer(Metric.miniFieldW))
            }
        }
        cells.append(noteLabel(note))
        return row(cells)
    }

    // MARK: 构建界面

    private func build() {
        guard let content = window?.contentView else { return }

        hostBox.placeholder = "172.17.2.15 或域名"
        portBox.placeholder = "7887"
        userBox.placeholder = "admin"
        relayBox.placeholder = "7899"
        bypassBox.placeholder = "空格分隔，如 *.hd123.com"

        modeField.setItems(VPNMode.allCases.map { $0.title })
        modeField.onChange = { [weak self] _ in self?.modeChanged() }

        dockSwitch.controlSize = .regular
        dockSwitch.translatesAutoresizingMaskIntoConstraints = false

        testButton.target = self
        testButton.action = #selector(runTest)
        testButton.bezelStyle = .rounded
        testButton.controlSize = .large
        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.widthAnchor.constraint(equalToConstant: 116).isActive = true

        let save = NSButton(title: "保存并应用", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.controlSize = .large
        save.keyEquivalent = "\r"
        save.translatesAutoresizingMaskIntoConstraints = false
        save.widthAnchor.constraint(equalToConstant: 132).isActive = true

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .large
        cancel.keyEquivalent = "\u{1b}"
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.widthAnchor.constraint(equalToConstant: 92).isActive = true

        let buttons = NSStackView(views: [testButton, spacer(), cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .centerY

        let note = NSTextField(wrappingLabelWithString:
            "保存后立即重启本地中继并按新参数重挂系统代理；「卸载公司代理…」会连同配置、日志、开机自启一并清除。")
        note.font = .systemFont(ofSize: Metric.small)
        note.textColor = .secondaryLabelColor
        note.isSelectable = false
        note.preferredMaxLayoutWidth = Metric.cardInnerW

        resultHolder.orientation = .vertical
        resultHolder.alignment = .width
        resultHolder.spacing = 0

        let cardProxy = CardView(column([
            formRow("代理地址", control: hostBox,
                    miniLabel: "端口", miniControl: portBox, note: "内网地址或域名"),
            formRow("用户名", control: userBox,
                    miniLabel: "密码", miniControl: passBox, note: "为空时浏览器会弹认证"),
        ]))

        let cardVPN = CardView(column([
            formRow("方式", control: modeField, note: "有 ppp0 走 HD-VPN，否则走路由器 L2TP"),
        ]))

        let cardRelay = CardView(column([
            formRow("中继端口", control: relayBox, note: "系统代理指向 127.0.0.1:该端口"),
            formRow("直连白名单", control: bypassBox, controlWidth: Metric.controlSpanW,
                    note: "空格分隔，如 *.hd123.com"),
        ]))

        let cardLook = CardView(column([
            formRow("在程序坞显示", control: dockSwitch, note: "开启后常驻程序坞，右键图标可快速开关代理"),
        ]))

        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        for v in [section("公司 3proxy 代理"), cardProxy,
                  section("VPN 接入方式"), cardVPN,
                  section("本地中继与白名单"), cardRelay,
                  section("外观"), cardLook,
                  resultHolder,
                  buttons, note] as [NSView] {
            mainStack.addArrangedSubview(v)
        }
        mainStack.setCustomSpacing(Metric.cardGap + 6, after: cardProxy)
        mainStack.setCustomSpacing(Metric.cardGap + 6, after: cardVPN)
        mainStack.setCustomSpacing(Metric.cardGap + 6, after: cardRelay)
        mainStack.setCustomSpacing(12, after: cardLook)
        mainStack.setCustomSpacing(10, after: resultHolder)

        content.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Metric.margin),
            mainStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Metric.margin),
            mainStack.topAnchor.constraint(equalTo: content.topAnchor, constant: Metric.margin),
        ])

        for v in [cardProxy, cardVPN, cardRelay, cardLook, buttons, note, resultHolder] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        }

        resizeToFit()
    }

    /// 内容变化后重算窗口高度（保持顶边不动）
    private func resizeToFit() {
        guard let win = window, let content = win.contentView else { return }
        content.layoutSubtreeIfNeeded()
        mainStack.layoutSubtreeIfNeeded()
        let need = ceil(mainStack.fittingSize.height) + Metric.margin * 2
        let h = max(need, 460)
        let current = win.contentRect(forFrameRect: win.frame).height
        guard abs(current - h) > 0.5 else { return }
        let top = win.frame.maxY
        win.setContentSize(NSSize(width: Metric.windowW, height: h))
        win.setFrameOrigin(NSPoint(x: win.frame.minX, y: top - win.frame.height))
    }

    // MARK: 数据绑定

    private func load() {
        hostBox.stringValue = cfg.host
        portBox.stringValue = String(cfg.port)
        userBox.stringValue = cfg.user
        passBox.stringValue = cfg.pass
        relayBox.stringValue = String(cfg.relayPort)
        bypassBox.stringValue = cfg.bypass
        modeField.selectItem(at: VPNMode.allCases.firstIndex(of: cfg.vpnMode) ?? 0)
        dockSwitch.state = cfg.showInDock ? .on : .off
    }

    @objc private func modeChanged() {}

    private func collect() -> Config? {
        var c = cfg
        let host = hostBox.stringValue.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { bad("代理地址不能为空"); return nil }
        guard let port = Int(portBox.stringValue.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(port) else {
            bad("代理端口需为 1–65535"); return nil
        }
        guard let rport = Int(relayBox.stringValue.trimmingCharacters(in: .whitespaces)),
              (1024...65535).contains(rport) else {
            bad("中继端口需为 1024–65535"); return nil
        }
        c.host = host
        c.port = port
        c.user = userBox.stringValue.trimmingCharacters(in: .whitespaces)
        c.pass = passBox.stringValue
        c.relayPort = rport
        c.bypass = bypassBox.stringValue.trimmingCharacters(in: .whitespaces)
        c.vpnMode = VPNMode.allCases[max(0, modeField.selectedIndex)]
        c.showInDock = dockSwitch.state == .on
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

    // MARK: 连接测试

    @objc private func runTest() {
        guard let c = collect() else { return }
        testButton.isEnabled = false
        setResult(running("正在连接 \(c.host):\(c.port) …"), animated: true)

        DispatchQueue.global(qos: .userInitiated).async {
            let reachable = Shell.tcpAlive(c.host, UInt16(c.port), timeout: 3)
            var sections: [[InfoRow]] = []
            if reachable {
                sections.append([InfoRow("server.rack", "代理端口",
                                         "\(c.host):\(c.port) 可连接",
                                         valueTint: .labelColor)])
            } else {
                sections.append([InfoRow("exclamationmark.triangle.fill", "代理端口",
                                         "不可达（VPN 是否已连接？路由器 L2TP 请确认内网路由）",
                                         tint: .systemOrange, valueTint: .systemOrange)])
            }
            if reachable {
                let t0 = Date()
                let (_, code) = Shell.run("/usr/bin/curl",
                    ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "15",
                     "-x", c.upstreamURLWithAuth, "https://chatgpt.com/backend-api/me"], timeout: 20)
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let v = code.trimmingCharacters(in: .whitespacesAndNewlines)
                if v == "401" {
                    sections.append([
                        InfoRow("bolt.horizontal", "出口", "chatgpt.com → 401 正常",
                                tint: .systemGreen, valueTint: .labelColor),
                        InfoRow("clock", "耗时", "\(ms) ms"),
                    ])
                } else if v.isEmpty || v == "000" {
                    sections.append([InfoRow("exclamationmark.triangle.fill", "出口",
                                             "访问 chatgpt.com 失败（超时或被重置）",
                                             tint: .systemOrange, valueTint: .systemOrange)])
                } else {
                    sections.append([
                        InfoRow("dot.radiowaves.left.and.right", "出口", "chatgpt.com → HTTP \(v)"),
                        InfoRow("clock", "耗时", "\(ms) ms"),
                    ])
                }
            }

            DispatchQueue.main.async {
                self.testButton.isEnabled = true
                // 设置页里合成一整块，不要弹出式的多段分组
                let merged = [sections.flatMap { $0 }]
                self.setResult(InfoPanel.view(sections: merged, width: Metric.cardInnerW), animated: false)
            }
        }
    }

    /// 测试中的转圈提示
    private func running(_ text: String) -> NSView {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 14).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: Metric.small)
        l.textColor = .secondaryLabelColor

        let s = NSStackView(views: [spinner, l])
        s.orientation = .horizontal
        s.spacing = 8
        s.alignment = .centerY
        return CardView(s)
    }

    private func setResult(_ view: NSView?, animated: Bool) {
        for sv in resultHolder.arrangedSubviews {
            resultHolder.removeArrangedSubview(sv)
            sv.removeFromSuperview()
        }
        if let v = view {
            // InfoPanel 是手写 frame 布局，没有 intrinsic size：
            // 交给自动布局前必须把宽高钉死，否则会被压成 0 高、内容溢出
            let size = v.frame.size
            v.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                v.widthAnchor.constraint(equalToConstant: size.width),
                v.heightAnchor.constraint(equalToConstant: size.height),
            ])
            resultHolder.addArrangedSubview(v)
        }
        resizeToFit()
    }
}
