import Cocoa

// MARK: - 数据模型

/// 一颗指标胶囊：小图标 + 数值 + 说明。
/// 数值一栏用来放「耗时 0.68 秒」这种可一眼扫到的量，取代过去的「标签: 值」单元格。
struct InfoChip {
    var icon: String
    var tint: NSColor
    var value: String
    var caption: String
}

/// 一句陈述：图标 + 主句（+ 可选补充）。
/// 整句自由换行、没有固定列，所以点上去不会重排，也不像表单。
struct InfoFact {
    var icon: String
    var tint: NSColor
    var text: String
    var detail: String?

    init(_ icon: String, _ text: String, detail: String? = nil,
         tint: NSColor = .secondaryLabelColor) {
        self.icon = icon
        self.text = text
        self.detail = detail
        self.tint = tint
    }
}

/// 卡片顶部的语义基调：决定大图标、配色
enum InfoTone {
    case ok, warn, neutral

    var glyph: String {
        switch self {
        case .ok:      return "checkmark"
        case .warn:    return "exclamationmark"
        case .neutral: return "pause.fill"
        }
    }

    var tint: NSColor {
        switch self {
        case .ok:      return .systemGreen
        case .warn:    return .systemOrange
        case .neutral: return .secondaryLabelColor
        }
    }
}

struct InfoCardModel {
    var tone: InfoTone
    var title: String
    var subtitle: String?
    var chips: [InfoChip]
    var facts: [InfoFact]
    var footnote: String?

    init(tone: InfoTone,
         title: String,
         subtitle: String? = nil,
         chips: [InfoChip] = [],
         facts: [InfoFact] = [],
         footnote: String? = nil) {
        self.tone = tone
        self.title = title
        self.subtitle = subtitle
        self.chips = chips
        self.facts = facts
        self.footnote = footnote
    }
}

// MARK: - 配色

enum InfoTheme {

    /// 卡片底：接近纯白 / 深灰，比系统弹窗的灰底干净
    static var fill: NSColor {
        NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.145, alpha: 1)
                : NSColor(calibratedWhite: 0.995, alpha: 1)
        }
    }

    /// 1px 细边框，让卡片压在浅色窗口上也有边界
    static var edge: NSColor {
        NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.14)
                : NSColor(white: 0, alpha: 0.10)
        }
    }

    /// 胶囊底
    static var chipFill: NSColor {
        NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.10)
                : NSColor(white: 0, alpha: 0.055)
        }
    }

    static let radius: CGFloat = 18
}

// MARK: - 版面常量

private enum C {
    static let padH: CGFloat = 22
    static let padV: CGFloat = 20
    static let badge: CGFloat = 44
    static let textGap: CGFloat = 14
    static let blockGap: CGFloat = 16
    static let chipH: CGFloat = 26
    static let chipH_Gap: CGFloat = 6
    static let chipV_Gap: CGFloat = 6
    static let factGap: CGFloat = 8
    static let btnH: CGFloat = 31
    static let btnW: CGFloat = 84
    static let btnGap: CGFloat = 18
}

// MARK: - 翻转容器

private class Flipped: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - 内容构建

enum InfoCardBody {

    /// 弹窗默认宽度
    static let preferredWidth: CGFloat = 408

    /// 只算尺寸（给嵌进自动布局的场景用）
    static func size(_ m: InfoCardModel, width: CGFloat, showButton: Bool) -> NSSize {
        build(m, width: width, showButton: showButton, onClose: nil).size
    }

    static func view(_ m: InfoCardModel, width: CGFloat = preferredWidth,
                     showButton: Bool = false,
                     onClose: (() -> Void)? = nil) -> NSView {
        let out = build(m, width: width, showButton: showButton, onClose: onClose)
        out.view.frame = NSRect(origin: .zero, size: out.size)
        return out.view
    }

    // MARK: 组装

    private static func build(_ m: InfoCardModel, width: CGFloat, showButton: Bool,
                              onClose: (() -> Void)?) -> (view: NSView, size: NSSize) {
        let innerW = width - C.padH * 2
        var blocks: [(NSView, CGFloat)] = []

        // 1. 顶部：大图标 + 标题 + 一句说明
        let hero = heroView(m, width: innerW)
        blocks.append(hero)

        // 2. 指标胶囊
        if !m.chips.isEmpty {
            let chips = chipsView(m.chips, width: innerW)
            blocks.append(chips)
        }

        // 3. 陈述句
        if !m.facts.isEmpty {
            var all: [NSView] = []
            var h: CGFloat = 0
            for (i, f) in m.facts.enumerated() {
                let v = factView(f, width: innerW)
                all.append(v)
                h += v.frame.height
                if i < m.facts.count - 1 { h += C.factGap }
            }
            let box = Flipped(frame: NSRect(x: 0, y: 0, width: innerW, height: ceil(h)))
            var y: CGFloat = 0
            for v in all {
                v.frame.origin = NSPoint(x: 0, y: y)
                box.addSubview(v)
                y += v.frame.height + C.factGap
            }
            blocks.append((box, box.frame.height))
        }

        // 4. 脚注
        if let fn = m.footnote, !fn.isEmpty {
            let font = NSFont.systemFont(ofSize: 11.5)
            let h = measure(fn, font: font, width: innerW)
            let label = makeLabel(NSAttributedString(string: fn, attributes: [
                .font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            label.frame = NSRect(x: 0, y: 0, width: innerW, height: h)
            let box = Flipped(frame: NSRect(x: 0, y: 0, width: innerW, height: h))
            box.addSubview(label)
            blocks.append((box, h))
        }

        // 5. 高度：上内边距 + 各块 + 块间距 + 按钮区 + 下内边距
        var contentH: CGFloat = 0
        for (i, b) in blocks.enumerated() {
            contentH += b.1
            if i < blocks.count - 1 { contentH += C.blockGap }
        }
        var total = C.padV + ceil(contentH) + C.padV
        if showButton { total += C.btnGap + C.btnH }

        let root = Flipped(frame: NSRect(x: 0, y: 0, width: width, height: total))
        var y: CGFloat = C.padV
        for b in blocks {
            b.0.frame.origin = NSPoint(x: C.padH, y: y)
            root.addSubview(b.0)
            y += b.1 + C.blockGap
        }

        if showButton {
            let btn = CardButton(title: "好", onTap: onClose)
            btn.frame = NSRect(x: width - C.padH - C.btnW,
                               y: total - C.padV - C.btnH,
                               width: C.btnW, height: C.btnH)
            root.addSubview(btn)
        }

        return (root, NSSize(width: width, height: total))
    }

    // MARK: 顶部

    private static func heroView(_ m: InfoCardModel, width: CGFloat) -> (NSView, CGFloat) {
        let tone = m.tone

        let badge = NSView(frame: NSRect(x: 0, y: 0, width: C.badge, height: C.badge))
        badge.wantsLayer = true
        badge.layer?.cornerRadius = C.badge / 2
        badge.layer?.cornerCurve = .continuous
        badge.layer?.backgroundColor = tone.tint.withAlphaComponent(0.14).cgColor

        let icon = NSImageView(frame: NSRect(origin: .zero, size: NSSize(width: 22, height: 22)))
        icon.image = UIStatus.image(tone.glyph, color: tone.tint, size: 19)
        icon.imageScaling = .scaleNone
        icon.imageAlignment = .alignCenter
        icon.frame.origin = NSPoint(x: (C.badge - 22) / 2, y: (C.badge - 22) / 2)
        badge.addSubview(icon)

        let textX = C.badge + C.textGap
        let textW = width - textX

        let titleFont = NSFont.systemFont(ofSize: 17, weight: .semibold)
        let titleH = measure(m.title, font: titleFont, width: textW)
        let title = makeLabel(NSAttributedString(string: m.title, attributes: [
            .font: titleFont, .foregroundColor: NSColor.labelColor]))
        title.frame = NSRect(x: textX, y: 1, width: textW, height: titleH)

        var subH: CGFloat = 0
        var sub: NSTextField?
        if let s = m.subtitle, !s.isEmpty {
            let f = NSFont.systemFont(ofSize: 12.5)
            subH = measure(s, font: f, width: textW)
            let l = makeLabel(NSAttributedString(string: s, attributes: [
                .font: f, .foregroundColor: NSColor.secondaryLabelColor]))
            l.frame = NSRect(x: textX, y: titleH + 4, width: textW, height: subH)
            sub = l
        }

        let textH = titleH + (sub == nil ? 0 : 4 + subH)
        let h = max(C.badge, textH)

        let box = Flipped(frame: NSRect(x: 0, y: 0, width: width, height: ceil(h)))
        // 文字块在徽标里垂直居中
        let dy = max(0, (h - textH) / 2)
        title.frame.origin.y += dy
        box.addSubview(title)
        if let sub {
            sub.frame.origin.y += dy
            box.addSubview(sub)
        }
        var badgeFrame = badge.frame
        badgeFrame.origin.y = max(0, (h - C.badge) / 2)
        badge.frame = badgeFrame
        box.addSubview(badge)

        return (box, box.frame.height)
    }

    // MARK: 胶囊

    private static func chipsView(_ chips: [InfoChip], width: CGFloat) -> (NSView, CGFloat) {
        let views = chips.map { chipView($0) }

        // 贪心换行
        var rows: [[NSView]] = []
        var current: [NSView] = []
        var used: CGFloat = 0
        for v in views {
            let w = v.frame.width
            if !current.isEmpty && used + C.chipH_Gap + w > width {
                rows.append(current)
                current = []
                used = 0
            }
            used += (current.isEmpty ? 0 : C.chipH_Gap) + w
            current.append(v)
        }
        if !current.isEmpty { rows.append(current) }

        let h = CGFloat(rows.count) * C.chipH + CGFloat(max(0, rows.count - 1)) * C.chipV_Gap
        let box = Flipped(frame: NSRect(x: 0, y: 0, width: width, height: ceil(h)))

        var y: CGFloat = 0
        for row in rows {
            var x: CGFloat = 0
            for v in row {
                v.frame.origin = NSPoint(x: x, y: y)
                box.addSubview(v)
                x += v.frame.width + C.chipH_Gap
            }
            y += C.chipH + C.chipV_Gap
        }
        return (box, box.frame.height)
    }

    private static func chipView(_ chip: InfoChip) -> NSView {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let capFont = NSFont.systemFont(ofSize: 11.5)
        let s = NSMutableAttributedString()
        s.append(UIStatus.inline(chip.icon, color: chip.tint, font: font, size: 11))
        s.append(NSAttributedString(string: "  " + chip.value,
                                    attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        s.append(NSAttributedString(string: " " + chip.caption,
                                    attributes: [.font: capFont, .foregroundColor: NSColor.secondaryLabelColor]))

        // 直接画字：NSTextField 在单行高度下会把超出部分换行后裁掉（出现「682 ms 耗」）
        let w = ceil(s.size().width) + 24
        return ChipView(text: s, width: w)
    }

    // MARK: 陈述句

    private static func factView(_ f: InfoFact, width: CGFloat) -> NSView {
        let font = NSFont.systemFont(ofSize: 13)
        let textFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let detailFont = NSFont.systemFont(ofSize: 12.5)

        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2.5
        p.headIndent = 19          // 换行后挂在图标右侧，读起来不会断列
        p.firstLineHeadIndent = 0

        let s = NSMutableAttributedString()
        s.append(UIStatus.inline(f.icon, color: f.tint, font: font, size: 12))
        s.append(NSAttributedString(string: "  " + f.text,
                                    attributes: [.font: textFont, .foregroundColor: NSColor.labelColor]))
        if let d = f.detail, !d.isEmpty {
            s.append(NSAttributedString(string: "　" + d,
                                        attributes: [.font: detailFont,
                                                     .foregroundColor: NSColor.secondaryLabelColor]))
        }
        s.addAttributes([.paragraphStyle: p], range: NSRange(location: 0, length: s.length))

        let h = measure(s, width: width)
        let label = makeLabel(s)
        label.frame = NSRect(x: 0, y: 0, width: width, height: h)
        let box = Flipped(frame: NSRect(x: 0, y: 0, width: width, height: ceil(h)))
        box.addSubview(label)
        return box
    }

    // MARK: 工具

    /// 不可选中、不可编辑：点上去不会抢焦点，也就不会重排
    private static func makeLabel(_ s: NSAttributedString) -> NSTextField {
        let f = NSTextField(frame: .zero)
        f.isBezeled = false
        f.isBordered = false
        f.drawsBackground = false
        f.isEditable = false
        f.isSelectable = false
        f.focusRingType = .none
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 0
        f.cell?.wraps = true
        f.cell?.isScrollable = false
        f.cell?.truncatesLastVisibleLine = false
        f.attributedStringValue = s
        return f
    }

    private static func measure(_ s: NSAttributedString, width: CGFloat) -> CGFloat {
        let r = s.boundingRect(with: NSSize(width: width, height: 10_000),
                               options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(r.height) + 2
    }

    private static func measure(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        measure(NSAttributedString(string: text, attributes: [.font: font]), width: width)
    }
}

// MARK: - 胶囊

private final class ChipView: NSView {

    private let text: NSAttributedString

    init(text: NSAttributedString, width: CGFloat) {
        self.text = text
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: C.chipH))
        wantsLayer = true
        layer?.cornerRadius = C.chipH / 2
        layer?.cornerCurve = .continuous
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    /// 动态色必须在当前外观下取 CGColor，否则深色下会留下浅色底
    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            self?.layer?.backgroundColor = InfoTheme.chipFill.cgColor
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = text.size()
        text.draw(at: NSPoint(x: 12, y: (bounds.height - size.height) / 2))
    }
}

// MARK: - 胶囊形主按钮

private final class CardButton: NSButton {

    private let label: String
    private let onTap: (() -> Void)?

    init(title: String, onTap: (() -> Void)?) {
        self.label = title
        self.onTap = onTap
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        target = self
        action = #selector(tap)
        setButtonType(.momentaryChange)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    @objc private func tap() { onTap?() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        var fill = NSColor.controlAccentColor
        if isHighlighted {
            fill = fill.blended(withFraction: 0.16, of: .black) ?? fill
        }
        fill.setFill()
        path.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: (r.width - size.width) / 2,
                               y: (r.height - size.height) / 2),
                   withAttributes: attrs)
    }
}

// MARK: - 弹出

/// 自绘结果卡片窗口。
///
/// 不用 NSAlert 的原因：它的窗口底色是系统灰（浅色下偏脏），内容只能塞进 accessoryView，
/// 圆角、内边距、按钮样式都改不了。这里用一个无边框面板自己画。
final class InfoCard: NSObject {

    private static var current: InfoCard?

    private var panel: CardPanel?
    private var localMon: Any?
    private var globalMon: Any?

    static func present(_ model: InfoCardModel) {
        // 同一时刻只留一张，避免连点叠窗
        current?.dismiss()
        let card = InfoCard()
        current = card
        card.show(model)
    }

    private func show(_ model: InfoCardModel) {
        NSApp.activate(ignoringOtherApps: true)

        let width = InfoCardBody.preferredWidth
        let size = InfoCardBody.size(model, width: width, showButton: true)
        let content = InfoCardBody.view(model, width: width, showButton: true) { [weak self] in
            self?.dismiss()
        }

        let surface = CardSurface(frame: NSRect(origin: .zero, size: size))
        surface.addSubview(content)
        content.frame = surface.bounds

        let p = CardPanel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.contentView = surface
        p.onKey = { [weak self] _ in self?.dismiss() }

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2,
                                     y: vf.midY - size.height / 2 + 40))
        }

        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            p.animator().alphaValue = 1
        }
        p.invalidateShadow()
        panel = p

        // 点外部收起：稍等一拍再装监听，避免吃掉触发的这次点击
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard self?.panel != nil else { return }
            self?.localMon = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
                guard let self, let p = self.panel else { return e }
                if e.window !== p { self.dismiss() }
                return e
            }
            self?.globalMon = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
                self?.dismiss()
            }
        }
    }

    private func dismiss() {
        if let m = localMon { NSEvent.removeMonitor(m) }
        if let m = globalMon { NSEvent.removeMonitor(m) }
        localMon = nil
        globalMon = nil
        panel?.orderOut(nil)
        panel = nil
        if InfoCard.current === self { InfoCard.current = nil }
    }
}

// MARK: - 卡片底板

private final class CardSurface: NSView {

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            guard let l = self?.layer else { return }
            l.cornerRadius = InfoTheme.radius
            l.cornerCurve = .continuous
            l.masksToBounds = true
            l.backgroundColor = InfoTheme.fill.cgColor
            l.borderWidth = 1
            l.borderColor = InfoTheme.edge.cgColor
        }
    }
}

// MARK: - 面板

private final class CardPanel: NSPanel {

    var onKey: ((UInt16) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        // Esc / 回车 / 小键盘回车 都收起
        if event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 76 {
            onKey?(event.keyCode)
            return
        }
        super.keyDown(with: event)
    }
}
