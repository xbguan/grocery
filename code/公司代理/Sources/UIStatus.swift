import Cocoa

/// 状态图标工具：菜单 / 标签里用真正的 SF Symbol 图标表达「通 / 不通」，
/// 不再用 ✓ ✗ 这类字符（字符对齐差、也无法上色）。
enum UIStatus {

    /// 带颜色语义的状态图标
    /// - Parameters:
    ///   - on: 正常/连通
    ///   - onSymbol: 连通时的符号名
    ///   - offSymbol: 断开时的符号名
    static func symbol(on: Bool, on onSymbol: String, off offSymbol: String) -> (String, NSColor) {
        on ? (onSymbol, .systemGreen) : (offSymbol, .systemOrange)
    }

    /// 彩色 SF Symbol（不随文字颜色变化，用于内联图标）
    static func image(_ name: String, color: NSColor, size: CGFloat) -> NSImage? {
        let conf = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(conf) else { return nil }
        return img
    }

    /// 内联到富文本里的图标（菜单项 attributedTitle、NSTextField 用）
    static func inline(_ name: String, color: NSColor, font: NSFont) -> NSAttributedString {
        let size = max(font.pointSize, 11)
        guard let img = image(name, color: color, size: size) else {
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

    /// 组装一段「图标 + 文字」的菜单标题
    static func line(icon: String, color: NSColor, text: String, font: NSFont) -> NSAttributedString {
        let s = NSMutableAttributedString(attributedString: inline(icon, color: color, font: font))
        s.append(NSAttributedString(string: "  " + text, attributes: [.font: font]))
        return s
    }
}
