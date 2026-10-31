import Cocoa

// MARK: - 配色

/// 输入框 / 分组面板的填充色：跟随明暗外观的「半透明纯色」，
/// 不再依赖系统 bezel（bezel 在白色卡片上只剩底部一条阴影线，很脏）。
enum Palette {
    static let fieldFill = NSColor(name: nil) { ap in
        ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.085)
            : NSColor(white: 0, alpha: 0.055)
    }

    static let panelFill = NSColor(name: nil) { ap in
        ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.06)
            : NSColor(white: 0, alpha: 0.04)
    }

    static let hairline = NSColor(name: nil) { ap in
        ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.10)
            : NSColor(white: 0, alpha: 0.08)
    }
}

// MARK: - 圆角填充输入框

/// iOS 26/27 观感的输入框：无边框、无底部横线，纯填充 + 圆角，
/// 聚焦时描一圈强调色。文字用「固定行高的内层输入框垂直居中」实现，
/// 这样 12pt / 14pt 字号都能正中对齐（系统默认会把文字顶在上面）。
final class FieldBox: NSView, NSTextFieldDelegate {

    let field: NSTextField
    private var focused = false
    private let radius: CGFloat = 8

    var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    var placeholder: String {
        get { field.placeholderString ?? "" }
        set { field.placeholderString = newValue }
    }

    var isEnabled: Bool {
        get { field.isEnabled }
        set { field.isEnabled = newValue }
    }

    init(secure: Bool = false,
         font: NSFont = .systemFont(ofSize: Metric.body),
         leftInset: CGFloat = 10,
         trailingInset: CGFloat = 10,
         lines: Int = 1) {
        field = secure ? NSSecureTextField() : NSTextField()
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.usesSingleLineMode = lines == 1
        field.cell?.wraps = lines > 1
        field.cell?.isScrollable = lines == 1
        field.maximumNumberOfLines = lines
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        // 行高按字体实际高度给，上下不留余量 → 视觉正中
        let lineH = ceil(font.ascender - font.descender + font.leading)
        let boxH = lines == 1 ? Metric.fieldH : lineH * CGFloat(lines) + 14
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leftInset),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingInset),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: lineH * CGFloat(lines)),
            heightAnchor.constraint(equalToConstant: boxH),
        ])

        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        focused = true
        refresh()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        focused = false
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            guard let self, let layer else { return }
            layer.backgroundColor = (focused
                ? Palette.fieldFill.blended(withFraction: 0.35, of: .controlAccentColor) ?? Palette.fieldFill
                : Palette.fieldFill).cgColor
            layer.borderWidth = focused ? 1.5 : 0
            layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        }
    }
}

// MARK: - 密码框（眼睛按钮画在框内，不占列宽）

final class PasswordBox: NSView {

    private let secure = FieldBox(secure: true, trailingInset: 30)
    private let plain = FieldBox(secure: false, trailingInset: 30)
    private let eye = NSButton()
    private(set) var revealed = false

    var stringValue: String {
        get { revealed ? plain.stringValue : secure.stringValue }
        set {
            secure.stringValue = newValue
            plain.stringValue = newValue
        }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        for b in [secure, plain] {
            b.translatesAutoresizingMaskIntoConstraints = false
            addSubview(b)
        }
        plain.isHidden = true

        eye.isBordered = false
        eye.bezelStyle = .inline
        eye.focusRingType = .none
        eye.imagePosition = .imageOnly
        eye.contentTintColor = .tertiaryLabelColor
        eye.target = self
        eye.action = #selector(toggle)
        eye.translatesAutoresizingMaskIntoConstraints = false
        addSubview(eye)
        applyEye()

        NSLayoutConstraint.activate([
            secure.leadingAnchor.constraint(equalTo: leadingAnchor),
            secure.trailingAnchor.constraint(equalTo: trailingAnchor),
            secure.topAnchor.constraint(equalTo: topAnchor),
            secure.bottomAnchor.constraint(equalTo: bottomAnchor),

            plain.leadingAnchor.constraint(equalTo: leadingAnchor),
            plain.trailingAnchor.constraint(equalTo: trailingAnchor),
            plain.topAnchor.constraint(equalTo: topAnchor),
            plain.bottomAnchor.constraint(equalTo: bottomAnchor),

            eye.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            eye.centerYAnchor.constraint(equalTo: centerYAnchor),
            eye.widthAnchor.constraint(equalToConstant: 20),
            eye.heightAnchor.constraint(equalToConstant: 20),

            widthAnchor.constraint(equalToConstant: Metric.miniFieldW),
            heightAnchor.constraint(equalToConstant: Metric.fieldH),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggle() {
        let v = stringValue
        revealed.toggle()
        secure.isHidden = revealed
        plain.isHidden = !revealed
        stringValue = v
        applyEye()
        window?.makeFirstResponder(revealed ? plain.field : secure.field)
    }

    private func applyEye() {
        let conf = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        eye.image = NSImage(systemSymbolName: revealed ? "eye.slash" : "eye",
                            accessibilityDescription: revealed ? "隐藏密码" : "显示密码")?
            .withSymbolConfiguration(conf)
    }
}

// MARK: - 下拉框（和输入框同款外观）

/// 系统 NSPopUpButton 在 .large 下自带 40pt bezel，还会画自己的三角标
/// （和自定义箭头并排出现两个）。这里自己画控件，菜单仍然用 NSMenu。
final class SelectBox: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let popupMenu = NSMenu()
    private var items: [String] = []

    /// 选项变化回调（参数为新的 index）
    var onChange: ((Int) -> Void)?
    private(set) var selectedIndex = 0

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: Metric.body)
        titleLabel.textColor = .labelColor
        titleLabel.isSelectable = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.up.chevron.down",
                                accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        chevron.contentTintColor = .secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Metric.fieldH),
        ])

        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            self?.layer?.backgroundColor = Palette.fieldFill.cgColor
        }
    }

    // MARK: 数据

    func setItems(_ list: [String]) {
        items = list
        popupMenu.removeAllItems()
        for (i, t) in list.enumerated() {
            let item = NSMenuItem(title: t, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            popupMenu.addItem(item)
        }
        popupMenu.minimumWidth = bounds.width > 0 ? bounds.width : 300
        selectedIndex = min(selectedIndex, max(0, list.count - 1))
        applyTitle()
    }

    func selectItem(at index: Int) {
        guard index >= 0, index < items.count else { return }
        selectedIndex = index
        applyTitle()
        onChange?(index)
    }

    private func applyTitle() {
        guard selectedIndex < items.count else { return }
        titleLabel.stringValue = items[selectedIndex]
        for (i, item) in popupMenu.items.enumerated() {
            item.state = i == selectedIndex ? .on : .off
        }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag
        applyTitle()
        onChange?(selectedIndex)
    }

    // MARK: 交互

    override func mouseDown(with event: NSEvent) {
        popupMenu.minimumWidth = bounds.width
        popupMenu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: bounds.height + 4),
                   in: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
