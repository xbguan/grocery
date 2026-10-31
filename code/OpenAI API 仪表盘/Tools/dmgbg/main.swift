import AppKit
import CoreText

// 生成 DMG 安装窗口的背景图。
// 刻意做得极淡：只是把「拖到应用程序」这个动作画出来，不抢 App 图标的视觉。

let W: CGFloat = 660
let H: CGFloat = 420
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "bg.png"

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: Int(W), pixelsHigh: Int(H),
                                 bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write(Data("无法创建位图\n".utf8))
    exit(1)
}
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

// MARK: 底色

let space = CGColorSpaceCreateDeviceRGB()

// 冷调浅灰，和 App 图标的深色方块形成对比
if let g = CGGradient(colorsSpace: space, colors: [
    NSColor(srgbRed: 0.988, green: 0.992, blue: 0.994, alpha: 1).cgColor,
    NSColor(srgbRed: 0.898, green: 0.918, blue: 0.929, alpha: 1).cgColor,
] as CFArray, locations: [0, 1] as [CGFloat]) {
    ctx.drawLinearGradient(g,
                           start: CGPoint(x: W * 0.15, y: H),
                           end: CGPoint(x: W * 0.85, y: 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// 中间偏上一团极淡的品牌绿光，避免大面积纯灰显得塑料
if let glow = CGGradient(colorsSpace: space, colors: [
    NSColor(srgbRed: 0.094, green: 0.788, blue: 0.616, alpha: 0.10).cgColor,
    NSColor(srgbRed: 0.094, green: 0.788, blue: 0.616, alpha: 0).cgColor,
] as CFArray, locations: [0, 1] as [CGFloat]) {
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: W * 0.5, y: H * 0.56), startRadius: 0,
                           endCenter: CGPoint(x: W * 0.5, y: H * 0.56), endRadius: W * 0.46,
                           options: [])
}

// MARK: 中间箭头（图标中心连线高度）

let arrowY: CGFloat = H - 200   // Finder 坐标里图标中心在距顶 200 处
let mid = NSColor(srgbRed: 0.706, green: 0.737, blue: 0.765, alpha: 1)

ctx.saveGState()
ctx.setStrokeColor(mid.cgColor)
ctx.setLineWidth(2)
ctx.setLineCap(.butt)
ctx.setLineDash(phase: 0, lengths: [5, 6])
ctx.move(to: CGPoint(x: 252, y: arrowY))
ctx.addLine(to: CGPoint(x: 394, y: arrowY))
ctx.strokePath()
ctx.restoreGState()

let head = CGMutablePath()
head.move(to: CGPoint(x: 410, y: arrowY))
head.addLine(to: CGPoint(x: 392, y: arrowY + 8))
head.addLine(to: CGPoint(x: 392, y: arrowY - 8))
head.closeSubpath()
ctx.saveGState()
ctx.addPath(head)
ctx.setFillColor(mid.cgColor)
ctx.fillPath()
ctx.restoreGState()

// 起点的小圆点：非常轻的一处品牌绿，暗示"从这里开始"
ctx.saveGState()
ctx.setFillColor(NSColor(srgbRed: 0.094, green: 0.788, blue: 0.616, alpha: 0.85).cgColor)
ctx.fillEllipse(in: CGRect(x: 236, y: arrowY - 3.5, width: 7, height: 7))
ctx.restoreGState()

// MARK: 底部说明

func drawCentered(_ text: String, y: CGFloat, size: CGFloat,
                  color: NSColor, weight: NSFont.Weight) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: 0.2,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    var ascent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, nil, nil))
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.textPosition = CGPoint(x: (W - width) / 2, y: y)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

drawCentered("把左边的 App 拖到右边的「应用程序」文件夹",
             y: 76, size: 13, color: NSColor(srgbRed: 0.235, green: 0.263, blue: 0.290, alpha: 1),
             weight: .medium)

drawCentered("首次打开若提示「未验证的开发者」，请右键点按 App → 打开",
             y: 50, size: 11, color: NSColor(srgbRed: 0.494, green: 0.525, blue: 0.557, alpha: 1),
             weight: .regular)

gctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: outPath))
print("已生成背景图: \(outPath)  \(Int(W))×\(Int(H))")
