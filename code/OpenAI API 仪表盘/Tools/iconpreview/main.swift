import AppKit
import Foundation

// 对比菜单栏图标的几种画法（16pt 实际尺寸放大 8 倍观察）
// 用法：swiftc Logo.swift Tools/iconpreview/main.swift -o preview && ./preview out.png

func drawMark(_ ctx: CGContext, x: CGFloat, y: CGFloat, s: CGFloat, accent: Bool) {
    // 表盘弧 + 三柱：App 图标的缩小版
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.scaleBy(x: s / 18, y: s / 18)

    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(1.5)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: 9, y: 9.6), radius: 5.2,
               startAngle: 32 * .pi / 180, endAngle: 148 * .pi / 180, clockwise: false)
    ctx.strokePath()

    let xs: [CGFloat] = [4.2, 7.9, 11.6]
    let hs: [CGFloat] = [3.0, 4.4, 5.8]
    for i in 0..<3 {
        let r = CGRect(x: xs[i], y: 3.6, width: 2.2, height: hs[i])
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 1.1, cornerHeight: 1.1, transform: nil))
        ctx.setFillColor((accent && i == 2 ? NSColor.systemGreen : NSColor.white).cgColor)
        ctx.fillPath()
    }
    ctx.restoreGState()
}

func drawBars(_ ctx: CGContext, x: CGFloat, y: CGFloat, s: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.scaleBy(x: s / 18, y: s / 18)
    ctx.setFillColor(NSColor.white.cgColor)
    let xs: [CGFloat] = [3.0, 9.0, 15.0 - 3.0]
    let hs: [CGFloat] = [4.6, 7.2, 9.8]
    for i in 0..<3 {
        let r = CGRect(x: xs[i] - 1.5, y: 3.2, width: 3.0, height: hs[i])
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 1.3, cornerHeight: 1.3, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

func drawDial(_ ctx: CGContext, x: CGFloat, y: CGFloat, s: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.scaleBy(x: s / 18, y: s / 18)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(1.5)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: 9, y: 9), radius: 6.2,
               startAngle: 30 * .pi / 180, endAngle: 150 * .pi / 180, clockwise: false)
    ctx.strokePath()
    let a = 65 * Double.pi / 180
    ctx.move(to: CGPoint(x: 9, y: 9))
    ctx.addLine(to: CGPoint(x: 9 + cos(a) * 3.2, y: 9 + sin(a) * 3.2))
    ctx.strokePath()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: 8.0, y: 8.0, width: 2.0, height: 2.0))
    ctx.restoreGState()
}

let W = 720, H = 260
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

ctx.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

let zoom: CGFloat = 6
let base: CGFloat = 18 * zoom
drawMark(ctx, x: 40, y: 70, s: base, accent: false)
drawBars(ctx, x: 40 + base + 30, y: 70, s: base)
drawDial(ctx, x: 40 + (base + 30) * 2, y: 70, s: base)

// 小尺寸真实像素（18pt @2x = 36px），看是否糊
let small: CGFloat = 36
drawMark(ctx, x: 40, y: 20, s: small, accent: false)
drawBars(ctx, x: 100, y: 20, s: small)
drawDial(ctx, x: 160, y: 20, s: small)

gctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "preview.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("saved \(out)  顺序：左=弧+柱  中=三柱  右=表盘指针；下排为 36px 实际尺寸")
