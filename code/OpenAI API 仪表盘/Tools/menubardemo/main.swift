import AppKit
import Foundation

// 生成菜单栏图标的状态对照图：三种状态 × 明暗两种菜单栏
// 用法：swiftc Logo.swift Tools/menubardemo/main.swift -o membardemo && ./membardemo out.png

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    let r = NSRect(origin: .zero, size: image.size)
    image.draw(in: r)
    color.set()
    r.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

let scale: CGFloat = 3.0
let iconPt: CGFloat = 18
let iconPx = iconPt * scale
let pad: CGFloat = 30
let rowH: CGFloat = iconPx + 46
let colW: CGFloat = 168
let width: CGFloat = pad * 2 + colW * 3
let height: CGFloat = rowH * 2 + pad

let img = NSImage(size: NSSize(width: width, height: height))

func drawRow(_ ctx: CGContext, y: CGFloat, dark: Bool) {
    let bg = dark ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
                  : NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
    bg.setFill()
    ctx.fill(CGRect(x: 0, y: y, width: width, height: rowH))

    let ink = dark ? NSColor.white : NSColor.black
    let states: [(NSImage, String)] = [
        (MenuBarIcon.dial(), "正常：读取中"),
        (MenuBarIcon.idle(), "未配置 Key"),
        (MenuBarIcon.alert(), "出错：指针指到底")
    ]

    for (i, item) in states.enumerated() {
        let x = pad + CGFloat(i) * colW
        let iconRect = CGRect(x: x, y: y + rowH - 26 - iconPx, width: iconPx, height: iconPx)

        // 图标按 3 倍放大绘制，模拟 Retina 下的实际观感
        let icon = tinted(item.0, ink)
        ctx.saveGState()
        ctx.interpolationQuality = .high
        icon.draw(in: iconRect)
        ctx.restoreGState()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: dark ? NSColor.white.withAlphaComponent(0.62)
                                   : NSColor.black.withAlphaComponent(0.55)
        ]
        let str = NSAttributedString(string: item.1, attributes: attrs)
        str.draw(at: NSPoint(x: x, y: y + 12))
    }
}

img.lockFocus()
if let ctx = NSGraphicsContext.current?.cgContext {
    drawRow(ctx, y: pad + rowH, dark: false)
    drawRow(ctx, y: pad, dark: true)
    // 分隔线
    ctx.setFillColor(NSColor.gray.withAlphaComponent(0.35).cgColor)
    ctx.fill(CGRect(x: 0, y: pad + rowH - 0.5, width: width, height: 1))
}
img.unlockFocus()

guard CommandLine.arguments.count > 1 else {
    print("usage: membardemo <output.png>")
    exit(1)
}

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("render failed")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("saved \(CommandLine.arguments[1]) \(Int(width))x\(Int(height))")
