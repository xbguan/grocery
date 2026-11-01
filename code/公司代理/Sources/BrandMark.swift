import Cocoa

/// 品牌标识：一台「公司电脑」，屏幕里跑着双向流量。
///
/// 造型意图：
/// * 笔记本 = 公司发的这台机器（受管设备），比抽象的盾牌/箭头更具体
/// * 屏幕里的双向箭头 = 流量经中继进出，讲的是「代理」
/// * 青 → 紫 → 品红的角向渐变 = 有企业底色，又不至于像通用工具图标
///
/// 同一份几何同时给 App 图标（16~1024）和菜单栏模板图（18pt）用，
/// 避免两边画得不一样。菜单栏是单色模板图，只取轮廓，不带任何颜色。
enum BrandMark {

    // MARK: 配色（多色角向渐变 + 边缘反光 + 字形外发光）

    static let stops: [NSColor] = [
        NSColor(srgbRed: 0.10, green: 0.74, blue: 0.90, alpha: 1),   // 青
        NSColor(srgbRed: 0.42, green: 0.26, blue: 0.96, alpha: 1),   // 紫
        NSColor(srgbRed: 0.92, green: 0.24, blue: 0.72, alpha: 1),   // 品红
    ]
    static let accent = NSColor(srgbRed: 1.00, green: 0.60, blue: 0.86, alpha: 1)
    static let glow   = NSColor(srgbRed: 1.00, green: 0.62, blue: 0.88, alpha: 1)

    // MARK: 几何

    /// 粗箭头（横放，绝对坐标）；dir = 1 向右，-1 向左
    static func arrow(y: CGFloat, x0: CGFloat, x1: CGFloat,
                      shaft: CGFloat, dir: CGFloat) -> NSBezierPath {
        let headLen = shaft * 1.35
        let headHalf = shaft * 0.95
        let tipX = dir > 0 ? x1 : x0
        let tailX = dir > 0 ? x0 : x1
        let neckX = tipX - dir * headLen

        let p = NSBezierPath()
        p.move(to: NSPoint(x: tailX, y: y - shaft / 2))
        p.line(to: NSPoint(x: neckX, y: y - shaft / 2))
        p.line(to: NSPoint(x: neckX, y: y - headHalf))
        p.line(to: NSPoint(x: tipX, y: y))
        p.line(to: NSPoint(x: neckX, y: y + headHalf))
        p.line(to: NSPoint(x: neckX, y: y + shaft / 2))
        p.line(to: NSPoint(x: tailX, y: y + shaft / 2))
        p.close()
        return p
    }

    /// 笔记本字形：屏幕（箭头镂空）+ 底座
    /// - Parameter singleArrow: 小尺寸下只画一支箭头，两支会糊在一起
    static func laptop(in box: NSRect, singleArrow: Bool) -> [NSBezierPath] {
        let s = min(box.width, box.height)
        func px(_ u: CGFloat) -> CGFloat { box.minX + u * box.width }
        func py(_ u: CGFloat) -> CGFloat { box.minY + u * box.height }

        let screen = NSBezierPath(roundedRect: NSRect(x: px(0.15), y: py(0.44),
                                                      width: px(0.85) - px(0.15),
                                                      height: py(0.90) - py(0.44)),
                                  xRadius: s * 0.055, yRadius: s * 0.055)

        let shaft = s * (singleArrow ? 0.115 : 0.068)
        if singleArrow {
            screen.append(arrow(y: py(0.670), x0: px(0.255), x1: px(0.745),
                                shaft: shaft, dir: 1))
        } else {
            screen.append(arrow(y: py(0.715), x0: px(0.255), x1: px(0.745),
                                shaft: shaft, dir: 1))
            screen.append(arrow(y: py(0.580), x0: px(0.255), x1: px(0.745),
                                shaft: shaft, dir: -1))
        }
        screen.windingRule = .evenOdd

        let base = NSBezierPath(roundedRect: NSRect(x: px(0.06), y: py(0.305),
                                                    width: px(0.94) - px(0.06),
                                                    height: py(0.372) - py(0.305)),
                                xRadius: s * 0.035, yRadius: s * 0.035)
        return [screen, base]
    }

    // MARK: App 图标

    static func icon(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true

        let inset = size * 0.085
        let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let radius = size * 0.225
        let body = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // 1. 主体多色角向渐变
        NSGradient(colors: stops)!.draw(in: body, angle: -68)

        NSGraphicsContext.saveGraphicsState()
        body.addClip()

        // 2. 左上柔白高光（线性，铺满整个底板，不会留下圆形边界）
        NSGradient(colors: [NSColor(white: 1, alpha: 0.15), NSColor(white: 1, alpha: 0)])!
            .draw(in: body, angle: -68)

        // 3. 底部彩色反光：45% 高度内线性淡出
        NSGradient(colors: [accent.withAlphaComponent(0.55),
                            accent.withAlphaComponent(0.16),
                            accent.withAlphaComponent(0)])!
            .draw(in: NSRect(x: rect.minX, y: rect.minY,
                             width: rect.width, height: rect.height * 0.45),
                  angle: 90)

        NSGraphicsContext.restoreGraphicsState()

        // 5. 1px 玻璃亮边
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.004, dy: size * 0.004),
                                xRadius: radius, yRadius: radius)
        edge.lineWidth = size * 0.008
        NSColor(white: 1, alpha: 0.20).setStroke()
        edge.stroke()

        let g = size * 0.54
        let box = NSRect(x: (size - g) / 2, y: (size - g) / 2, width: g, height: g)
        let paths = laptop(in: box, singleArrow: false)

        // 6. 字形外发光：先铺一层柔光，白字形才像"透亮"而不是"贴纸"
        NSGraphicsContext.saveGraphicsState()
        let glowShadow = NSShadow()
        glowShadow.shadowColor = glow.withAlphaComponent(0.75)
        glowShadow.shadowBlurRadius = size * 0.055
        glowShadow.shadowOffset = NSSize(width: 0, height: 0)
        glowShadow.set()
        NSColor.white.withAlphaComponent(0.9).setFill()
        for p in paths { p.fill() }
        NSGraphicsContext.restoreGraphicsState()

        // 7. 实心白 + 极轻投影
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.18)
        shadow.shadowBlurRadius = size * 0.016
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.005)
        shadow.set()
        NSColor.white.setFill()
        for p in paths { p.fill() }
        NSGraphicsContext.restoreGraphicsState()

        img.unlockFocus()
        return img
    }

    // MARK: 菜单栏模板图

    /// 菜单栏是单色模板图，系统会按菜单栏明暗自动反色。
    ///
    /// 这里**不复用 App 图标的比例**：图标版的屏幕在 18pt 下只有 7.5pt 高、
    /// 宽却有 16pt，压成一条扁带。菜单栏版单独按「屏幕 1.47:1 + 底座紧贴」
    /// 重排，并用描边画（实心在小尺寸会糊成一团白）。
    static func menuImage(height: CGFloat = 18) -> NSImage {
        let s = height
        let w = height * 1.02
        let img = NSImage(size: NSSize(width: w, height: s))
        img.lockFocus()
        NSGraphicsContext.current?.shouldAntialias = true

        let lw = s * 0.075
        NSColor.black.setFill()
        NSColor.black.setStroke()

        // 屏幕（线框）
        let scrY = s * 0.255, scrH = s * 0.585
        let screen = NSBezierPath(roundedRect: NSRect(x: s * 0.065, y: scrY,
                                                      width: s * 0.870, height: scrH),
                                  xRadius: s * 0.072, yRadius: s * 0.072)
        screen.lineWidth = lw
        screen.stroke()

        // 屏幕里的一支箭头（流量方向）
        let a = arrow(y: scrY + scrH * 0.5, x0: s * 0.225, x1: s * 0.775,
                      shaft: s * 0.090, dir: 1)
        a.fill()

        // 底座：一条通栏的短线，代表机身
        let base = NSBezierPath()
        base.move(to: NSPoint(x: s * 0.055, y: s * 0.155))
        base.line(to: NSPoint(x: s * 0.965, y: s * 0.155))
        base.lineWidth = s * 0.070
        base.lineCapStyle = .round
        base.stroke()

        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
