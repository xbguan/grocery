import Cocoa

/// 状态图标工具：菜单 / 标签里用真正的 SF Symbol 图标表达「通 / 不通」，
/// 不再用 ✓ ✗ 这类字符（字符对齐差、也无法上色）。
enum UIStatus {

    /// 顶部状态区的图标列宽：图标占 0..column，文字一律从 column 起
    static let statusColumn: CGFloat = 22
    /// 顶部第一行的第二列（状态文字之后、详情之前）
    static let statusDetailColumn: CGFloat = 80

    /// 彩色 SF Symbol（不随文字颜色变化，用于内联图标）
    static func image(_ name: String, color: NSColor, size: CGFloat) -> NSImage? {
        let conf = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(conf) else { return nil }
        return img
    }

    /// 内联到富文本里的图标（菜单项 attributedTitle、NSTextField 用）
    /// - Parameter size: 不传时跟随字号；顶部表头这类地方可以单独给更小的值
    static func inline(_ name: String, color: NSColor, font: NSFont,
                       size: CGFloat? = nil) -> NSAttributedString {
        let pt = size ?? max(font.pointSize, 11)
        guard let img = image(name, color: color, size: pt) else {
            return NSAttributedString(string: "")
        }
        let att = NSTextAttachment()
        att.image = img
        att.bounds = NSRect(x: 0,
                            y: (font.capHeight - img.size.height) / 2,
                            width: img.size.width,
                            height: img.size.height)
        return NSAttributedString(attachment: att)
    }

    /// 普通菜单项左侧的单色模板图标（跟随菜单明暗/选中状态）
    static func menuImage(_ name: String, size: CGFloat = 13) -> NSImage? {
        let conf = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(conf)
        img?.isTemplate = true
        return img
    }

    /// 带制表位的文字属性。行首放图标再跟一个 `\t`，文字就跳到第一列；
    /// 下面那行以 `\t` 开头即可让两行文字左边缘严格对齐。
    static func columnAttrs(font: NSFont, color: NSColor?,
                            tabs: [CGFloat] = [statusColumn]) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.tabStops = tabs.map { NSTextTab(textAlignment: .left, location: $0, options: [:]) }
        p.defaultTabInterval = tabs.last ?? statusColumn
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: p]
        if let color { attrs[.foregroundColor] = color }
        return attrs
    }

    /// 顶部第一行的文字：状态词 + 详情两列。
    /// 图标不放在文字里，而是用菜单项自己的 `image`，
    /// 这样它能和下方各菜单项的图标严格同列。
    static func statusHead(state: String, detail: String,
                           font: NSFont, detailColumn: CGFloat = 46) -> NSAttributedString {
        let s = NSMutableAttributedString(string: state)
        s.append(NSAttributedString(
            string: "\t" + detail,
            attributes: columnAttrs(font: font, color: .labelColor, tabs: [detailColumn])))
        s.addAttributes(columnAttrs(font: font, color: .labelColor, tabs: [detailColumn]),
                        range: NSRange(location: 0, length: s.length))
        return s
    }

    /// 透明占位图：让没有图标的行也占住图标列，文字才能与其它行对齐
    static var blankIcon: NSImage {
        let img = NSImage(size: NSSize(width: 12, height: 1))
        img.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 1).fill()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    /// 顶部第二行：文字已由菜单项图标列对齐，无需再缩进，可穿插小图标
    static func subLine(_ pieces: [Piece], font: NSFont, iconSize: CGFloat) -> NSAttributedString {
        let s = NSMutableAttributedString(string: "")
        for p in pieces {
            switch p {
            case .text(let t):
                s.append(NSAttributedString(string: t,
                                            attributes: columnAttrs(font: font, color: .secondaryLabelColor)))
            case .icon(let name):
                s.append(inline(name, color: .secondaryLabelColor, font: font, size: iconSize))
            case .tinted(let name, let color):
                s.append(inline(name, color: color, font: font, size: iconSize))
            }
        }
        return s
    }

    enum Piece {
        case text(String)
        case icon(String)                    // 次要灰
        case tinted(String, NSColor)         // 带语义色
    }
}
