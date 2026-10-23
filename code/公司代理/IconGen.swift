import Cocoa

// 生成 App 图标：深蓝渐变圆角矩形 + building.2.fill 白色字形
func makeIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let inset = size * 0.085
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.215, yRadius: size * 0.215)

    let grad = NSGradient(colors: [
        NSColor(srgbRed: 0.24, green: 0.45, blue: 0.80, alpha: 1.0),
        NSColor(srgbRed: 0.07, green: 0.16, blue: 0.38, alpha: 1.0),
    ])!
    grad.draw(in: path, angle: -70)

    // 轻微顶部增亮，增加立体感（渐变过渡，避免硬边）
    let highlight = NSGradient(colors: [
        NSColor(white: 1.0, alpha: 0.16),
        NSColor(white: 1.0, alpha: 0.0),
    ])!
    highlight.draw(in: path, relativeCenterPosition: NSPoint(x: 0, y: 0.85))

    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "building.2.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let w = size * 0.46
        let h = w * (sym.size.height / max(sym.size.width, 1))
        let target = NSRect(x: (size - w) / 2, y: (size - h) / 2 - size * 0.01, width: w, height: h)
        sym.draw(in: target)
    }

    img.unlockFocus()
    return img
}

func writePNG(_ image: NSImage, _ path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let specs: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in specs {
    writePNG(makeIcon(size: size), "\(outDir)/\(name).png")
}
print("icons written to \(outDir)")
