import Cocoa

// MARK: - 数据

/// 信息面板里的一行：图标 + 标签 + 值
struct InfoRow {
    var icon: String
    var tint: NSColor
    var title: String
    var value: String
    var valueTint: NSColor

    init(_ icon: String, _ title: String, _ value: String,
         tint: NSColor = .secondaryLabelColor,
         valueTint: NSColor = .labelColor) {
        self.icon = icon
        self.title = title
        self.value = value
        self.tint = tint
        self.valueTint = valueTint
    }
}

/// 面板顶部的一行总状态
struct InfoHeadline {
    var icon: String
    var tint: NSColor
    var text: String
}

// MARK: - 版面常量

private enum L {
    static let iconX: CGFloat = 16
    static let icon: CGFloat = 16
    static let titleX: CGFloat = 42
    static let titleW: CGFloat = 76
    static let valueX: CGFloat = 124
    static let rightPad: CGFloat = 16
    static let padV: CGFloat = 9
    static let gap: CGFloat = 10
    static let radius: CGFloat = 10
}

// MARK: - 翻转容器 / 分组底

private class Flipped: NSView {
    override var isFlipped: Bool { true }
}

private final class PanelBox: Flipped {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = L.radius
        layer?.cornerCurve = .continuous
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            self?.layer?.backgroundColor = Palette.panelFill.cgColor
        }
    }
}

// MARK: - 面板

/// 「测试连接」「代理状态」共用的信息面板。
///
/// 和以前的实现（一整块制表位富文本）最大的区别：
/// 每一行都是独立的、**不可选中**的静态标签，值换行后由列坐标决定位置，
/// 鼠标点上去不会重新排版、也不会出现缩进跳动。
enum InfoPanel {

    static let alertWidth: CGFloat = 440

    static func view(headline: InfoHeadline? = nil,
                     sections: [[InfoRow]],
                     footnote: String? = nil,
                     width: CGFloat = alertWidth) -> NSView {
        var blocks: [(view: NSView, height: CGFloat)] = []

        if let h = headline {
            let v = headlineView(h, width: width)
            blocks.append((v, v.frame.height))
        }
        for rows in sections where !rows.isEmpty {
            let v = groupView(rows, width: width)
            blocks.append((v, v.frame.height))
        }
        if let fn = footnote, !fn.isEmpty {
            let font = NSFont.systemFont(ofSize: 11.5)
            let w = width - L.iconX * 2
            let h = measure(fn, font: font, width: w) + 2
            let label = makeLabel(fn, font: font, color: .secondaryLabelColor, align: .left)
            label.frame = NSRect(x: L.iconX, y: 0, width: w, height: h)
            let wrap = Flipped(frame: NSRect(x: 0, y: 0, width: width, height: h))
            wrap.addSubview(label)
            blocks.append((wrap, h))
        }

        let total = blocks.reduce(0) { $0 + $1.height }
            + L.gap * CGFloat(max(0, blocks.count - 1))
        let root = Flipped(frame: NSRect(x: 0, y: 0, width: width, height: ceil(total)))

        var y: CGFloat = 0
        for b in blocks {
            b.view.frame.origin = NSPoint(x: 0, y: y)
            root.addSubview(b.view)
            y += b.height + L.gap
        }
        return root
    }

    // MARK: 顶部状态行

    private static func headlineView(_ h: InfoHeadline, width: CGFloat) -> NSView {
        let hgt: CGFloat = 30
        let box = Flipped(frame: NSRect(x: 0, y: 0, width: width, height: hgt))

        let icon = NSImageView(frame: NSRect(x: L.iconX, y: (hgt - 18) / 2, width: 18, height: 18))
        icon.image = UIStatus.image(h.icon, color: h.tint, size: 16)
        icon.imageScaling = .scaleNone
        icon.imageAlignment = .alignCenter
        box.addSubview(icon)

        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let label = makeLabel(h.text, font: font, color: h.tint, align: .left)
        label.frame = NSRect(x: L.titleX, y: (hgt - 18) / 2, width: width - L.titleX - L.rightPad, height: 18)
        box.addSubview(label)

        return box
    }

    // MARK: 分组

    private static func groupView(_ rows: [InfoRow], width: CGFloat) -> NSView {
        let titleFont = NSFont.systemFont(ofSize: 12.5)
        let valueFont = NSFont.systemFont(ofSize: 13)
        let valueW = width - L.valueX - L.rightPad

        var heights: [CGFloat] = []
        for r in rows {
            let vh = measure(r.value, font: valueFont, width: valueW)
            let th = measure(r.title, font: titleFont, width: L.titleW)
            heights.append(max(vh, th, 16) + L.padV * 2)
        }
        let seps = CGFloat(max(0, rows.count - 1))
        let boxH = heights.reduce(0, +) + seps

        let box = PanelBox(frame: NSRect(x: 0, y: 0, width: width, height: boxH))
        var y: CGFloat = 0

        for (i, r) in rows.enumerated() {
            let rh = heights[i]

            let icon = NSImageView(frame: NSRect(x: L.iconX, y: y + L.padV + 1, width: L.icon, height: L.icon))
            icon.image = UIStatus.image(r.icon, color: r.tint, size: 12)
            icon.imageScaling = .scaleNone
            icon.imageAlignment = .alignCenter
            box.addSubview(icon)

            let title = makeLabel(r.title, font: titleFont, color: .secondaryLabelColor, align: .left)
            title.frame = NSRect(x: L.titleX, y: y + L.padV, width: L.titleW, height: rh - L.padV * 2)
            box.addSubview(title)

            let value = makeLabel(r.value, font: valueFont, color: r.valueTint, align: .left)
            value.frame = NSRect(x: L.valueX, y: y + L.padV, width: valueW, height: rh - L.padV * 2)
            box.addSubview(value)

            y += rh
            if i < rows.count - 1 {
                let line = NSView(frame: NSRect(x: L.iconX, y: y, width: width - L.iconX - L.rightPad, height: 1))
                line.wantsLayer = true
                line.layer?.backgroundColor = Palette.hairline.cgColor
                box.addSubview(line)
                y += 1
            }
        }
        return box
    }

    // MARK: 工具

    /// 不可选中、不可编辑的静态文本 —— 点击不会抢焦点，也就不会重排
    private static func makeLabel(_ text: String, font: NSFont,
                                  color: NSColor, align: NSTextAlignment) -> NSTextField {
        let f = NSTextField(frame: .zero)
        f.isBezeled = false
        f.isBordered = false
        f.drawsBackground = false
        f.isEditable = false
        f.isSelectable = false
        f.focusRingType = .none
        f.font = font
        f.textColor = color
        f.alignment = align
        f.lineBreakMode = .byWordWrapping
        f.maximumNumberOfLines = 0
        f.cell?.wraps = true
        f.cell?.isScrollable = false
        f.cell?.truncatesLastVisibleLine = false
        f.stringValue = text
        return f
    }

    private static func measure(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return ceil(font.ascender - font.descender) }
        let r = (text as NSString).boundingRect(
            with: NSSize(width: width, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        return ceil(r.height)
    }
}
