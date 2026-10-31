import AppKit

// MARK: - 品牌色（OpenAI 视觉体系：中性近黑 + 单一品牌绿）

enum Brand {
    /// 品牌绿（浅色模式下稍深，保证对比度）
    static let green = NSColor(srgbRed: 0.043, green: 0.612, blue: 0.478, alpha: 1)
    /// 深色背景用的亮绿
    static let greenBright = NSColor(srgbRed: 0.180, green: 0.855, blue: 0.690, alpha: 1)
    static let greenCore = NSColor(srgbRed: 0.094, green: 0.788, blue: 0.616, alpha: 1)
}

// MARK: - 应用图标
//
// 设计思路：近黑圆角方块（OpenAI 的中性冷调）+ 表盘圆弧（仪表盘本体）
// + 三根递增柱（用量与花费）。只有最高的一根用品牌绿，其余为灰阶，
// 保持 OpenAI 那种「几乎全黑白、只留一处色彩」的克制。

enum LogoMark {
    /// 供 SwiftUI 使用
    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx, size: rect.width)
            return true
        }
    }

    /// 导出 PNG（尺寸即像素）
    static func pngData(size: CGFloat) -> Data? {
        let px = max(1, Int(size))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: px, height: px)
        guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx
        draw(in: gctx.cgContext, size: CGFloat(px))
        gctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    static func draw(in ctx: CGContext, size S: CGFloat, hexagonHint: Bool = false) {
        let rect = CGRect(x: 0.033 * S, y: 0.033 * S,
                          width: 0.934 * S, height: 0.934 * S)
        let radius = rect.width * 0.235
        let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // 底色：自上而下的冷灰渐变
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor(srgbRed: 0.160, green: 0.170, blue: 0.190, alpha: 1).cgColor,
                                       NSColor(srgbRed: 0.035, green: 0.035, blue: 0.042, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1] as [CGFloat]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: rect.midX, y: rect.maxY),
                                   end: CGPoint(x: rect.midX, y: rect.minY),
                                   options: [])
        }
        // 顶部柔光，制造亚克力的体积感
        if let g2 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [NSColor(white: 1, alpha: 0.15).cgColor,
                                        NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                               locations: [0, 1] as [CGFloat]) {
            ctx.drawRadialGradient(g2,
                                   startCenter: CGPoint(x: rect.midX, y: rect.maxY), startRadius: 0,
                                   endCenter: CGPoint(x: rect.midX, y: rect.maxY), endRadius: rect.width * 0.9,
                                   options: [])
        }
        ctx.restoreGState()

        // 内描边，让图标在任何底色上都有边界
        ctx.saveGState()
        ctx.addPath(body)
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
        ctx.setLineWidth(max(1.0, 0.0045 * S))
        ctx.strokePath()
        ctx.restoreGState()

        // 可选的六边形轮廓：只用几何暗示"品牌同源"，不复制任何商标图形
        if hexagonHint {
            let c = CGPoint(x: 0.5 * S, y: 0.455 * S)
            let r = 0.330 * S
            let hex = CGMutablePath()
            for i in 0..<6 {
                let a = CGFloat(i) * 60 * .pi / 180 + .pi / 2
                let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { hex.move(to: pt) } else { hex.addLine(to: pt) }
            }
            hex.closeSubpath()
            ctx.saveGState()
            ctx.addPath(hex)
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.16).cgColor)
            ctx.setLineWidth(max(1.0, 0.005 * S))
            ctx.setLineJoin(.round)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // —— 表盘圆弧
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(white: 0.94, alpha: 1).cgColor)
        ctx.setLineWidth(max(1.3, 0.0380 * S))
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: 0.5 * S, y: 0.4700 * S),
                   radius: 0.2350 * S,
                   startAngle: 26 * .pi / 180,
                   endAngle: 154 * .pi / 180,
                   clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()

        // —— 三根递增柱
        let barW = max(1.6, 0.0620 * S)
        let baseline = 0.290 * S
        let heights: [CGFloat] = [0.105, 0.175, 0.250]
        let xs: [CGFloat] = [0.395, 0.500, 0.605]
        let colors: [NSColor] = [NSColor(white: 0.34, alpha: 1),
                                 NSColor(white: 0.60, alpha: 1),
                                 Brand.greenCore]
        let barRadius = min(barW / 2, 0.0270 * S)

        for i in 0..<3 {
            let h = heights[i] * S
            let r = CGRect(x: xs[i] * S - barW / 2, y: baseline,
                           width: barW, height: h)
            let p = CGPath(roundedRect: r, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)
            ctx.addPath(p)
            ctx.setFillColor(colors[i].cgColor)
            ctx.fillPath()
        }
    }
}

// MARK: - 菜单栏图标（模板图，随菜单栏明暗自动反色）
//
// 三种状态共用同一套几何：240° 开口环（底部留缺口读作表盘）+ 中心轴点。
// 状态差异只体现在「指针」和「指示点」上，绝不换图形 ——
// 换形状会让菜单栏图标跳变，用户之前那个警告三角就是这么来的。

enum MenuBarIcon {
    /// 正常：环 + 指针（固定 55°，不跟随数据）+ 轴点
    static func dial() -> NSImage { render(.normal) }
    /// 未配置 Key：环空心 + 轴点，没有指针，显得"静止待机"
    static func idle() -> NSImage { render(.idle) }
    /// 出错（Key 无效 / 网络）：环 + 指针，缺口处多一个指示点
    static func alert() -> NSImage { render(.alert) }

    private enum State { case normal, idle, alert }

    private static func render(_ state: State) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let deg = Double.pi / 180

        let img = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // 直接走 CGContext 画弧：NSBezierPath.appendArc 默认是顺时针，
            // 会把弧画到圆心下方，方向和预期相反。
            let c = CGPoint(x: 9, y: 8.6)
            let r: CGFloat = 5.35

            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setStrokeColor(NSColor.black.cgColor)

            // 240° 开口环：底部留 60° 缺口
            ctx.setLineWidth(state == .idle ? 1.35 : 1.5)
            ctx.addArc(center: c, radius: r,
                       startAngle: -30 * deg, endAngle: 210 * deg,
                       clockwise: false)
            ctx.strokePath()

            // 指针：正常指向右上 55°（不跟随金额，只是标志）；
            // 异常时压到底部 270°，读作"指针掉到底了"，不再额外加感叹号之类图形
            if state != .idle {
                let angle = (state == .alert ? 270.0 : 55.0) * deg
                let len: CGFloat = state == .alert ? 3.4 : 3.7
                ctx.setLineWidth(1.5)
                ctx.move(to: c)
                ctx.addLine(to: CGPoint(x: c.x + cos(angle) * len,
                                        y: c.y + sin(angle) * len))
                ctx.strokePath()
            }

            // 中心轴点
            ctx.setFillColor(NSColor.black.cgColor)
            let hub: CGFloat = state == .idle ? 1.05 : 1.15
            ctx.fillEllipse(in: CGRect(x: c.x - hub, y: c.y - hub,
                                       width: hub * 2, height: hub * 2))
            ctx.restoreGState()
            return true
        }
        img.isTemplate = true
        return img
    }
}
