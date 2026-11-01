import Cocoa

// 生成 App 图标：调用 Sources/BrandMark.swift 里的同一份几何，保证图标与菜单栏一致
//
// 用法：icongen <输出目录>
// 注意：与 BrandMark.swift 一起编译，本文件不是 main.swift，所以用 @main 而不是顶层语句

@main
struct IconGenMain {

    /// 按**精确像素**写 PNG。
    ///
    /// 不能用 `image.tiffRepresentation`：`lockFocus` 会跟随屏幕的 2x 缩放，
    /// 16pt 的图会变成 32px 的位图，iconset 里每一档都翻倍，`iconutil` 会
    /// 因为尺寸对不上而丢掉 16/128 等档位。
    static func writePNG(_ image: NSImage, _ path: String, pixels: Int) {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = NSSize(width: pixels, height: pixels)

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high
            ctx.shouldAntialias = true
            image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                       from: .zero, operation: .copy, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    static func main() {
        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        let specs: [(String, CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, size) in specs {
            writePNG(BrandMark.icon(size: size), "\(outDir)/\(name).png", pixels: Int(size))
        }
        print("icons written to \(outDir)")
    }
}
