import Cocoa

/// 弹窗正文的「标签 + 值」两列表格。
///
/// NSAlert 的 informativeText 在多行时会被居中，长内容（比如网络服务清单）
/// 换行后完全没有对齐关系。这里改为把两块内容塞进 accessoryView：
/// 标签列右对齐、值列左对齐，值换行时靠悬挂缩进继续对齐值列。
enum AlertGrid {
    /// 标签右对齐到这一列
    static let labelColumn: CGFloat = 86
    /// 值从这一列起
    static let valueColumn: CGFloat = 96
    /// 默认宽度
    static let defaultWidth: CGFloat = 380

    static func view(_ rows: [(String, String)],
                     width: CGFloat = defaultWidth) -> NSTextField {
        let font = NSFont.systemFont(ofSize: 13)
        let text = NSMutableAttributedString()

        for (i, r) in rows.enumerated() {
            if i > 0 {
                text.append(NSAttributedString(string: "\n", attributes: attrs(font, .labelColor)))
            }
            // 空标签 = 分组之间的空行
            if r.0.isEmpty {
                if r.1.isEmpty {
                    text.append(NSAttributedString(string: " ", attributes: attrs(font, .labelColor)))
                } else {
                    // 只有值（脚注）：从值列起排
                    text.append(NSAttributedString(string: "\t\t" + r.1,
                                                    attributes: attrs(font, .secondaryLabelColor)))
                }
                continue
            }
            text.append(NSAttributedString(string: "\t" + r.0,
                                            attributes: attrs(font, .secondaryLabelColor)))
            text.append(NSAttributedString(string: "\t" + r.1,
                                            attributes: attrs(font, .labelColor)))
        }

        let f = NSTextField(wrappingLabelWithString: "")
        f.attributedStringValue = text
        f.preferredMaxLayoutWidth = width
        let h = f.cell?.cellSize(forBounds: NSRect(x: 0, y: 0,
                                                   width: width,
                                                   height: .greatestFiniteMagnitude)).height ?? 44
        f.frame = NSRect(x: 0, y: 0, width: width, height: ceil(h))
        return f
    }

    private static func attrs(_ font: NSFont, _ color: NSColor) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.tabStops = [
            NSTextTab(textAlignment: .right, location: labelColumn, options: [:]),
            NSTextTab(textAlignment: .left, location: valueColumn, options: [:]),
        ]
        p.firstLineHeadIndent = 0
        p.headIndent = valueColumn      // 值换行后继续对齐值列
        p.lineHeightMultiple = 1.12
        return [.font: font, .foregroundColor: color, .paragraphStyle: p]
    }
}
