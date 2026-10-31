import Cocoa

// MARK: - 模型

/// 顶部状态区的一行小信息（隧道 / 中继 / 自启）
struct MenuPill {
    var icon: String
    var text: String
    var tint: NSColor
}

struct MenuHeader {
    var on: Bool
    var title: String
    var detail: String
    var pills: [MenuPill]
    var note: String?
    /// 直连上游（会弹认证框）这类异常态
    var warn: Bool = false
}

struct MenuEntry {
    var id: String
    var title: String
    var icon: String
    var tint: NSColor = .secondaryLabelColor
    var key: String = ""
    /// nil = 普通项；true / false = 开关项
    var checked: Bool?
    var enabled: Bool = true
    var run: () -> Void
}

struct MenuModel {
    var header: MenuHeader
    var groups: [[MenuEntry]]
    /// 内容签名，用来判断要不要重建视图
    var version: String
}

// MARK: - 主题

enum MenuTheme {
    static let width: CGFloat = 332
    static let pad: CGFloat = 8
    static let rowH: CGFloat = 34
    static let radius: CGFloat = 14

    /// 半透明叠层：浅色用黑、深色用白，避免写死两套色
    static func layer(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
        NSColor(name: nil) { app in
            let isDark = app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor.white.withAlphaComponent(dark)
                : NSColor.black.withAlphaComponent(light)
        }
    }

    static var hairline: NSColor { layer(0.07, 0.10) }
    static var hoverFill: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.12) }
    static var normalTint: NSColor { layer(0.62, 0.72) }

    /// 面板底色：接近实心的浅色（这台机器上系统玻璃材质会退化成纯色，索性自己画）
    static var panelFill: NSColor {
        NSColor(name: nil) { app in
            let dark = app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return dark
                ? NSColor(calibratedWhite: 0.16, alpha: 1)
                : NSColor(calibratedWhite: 0.98, alpha: 1)
        }
    }
    /// 顶部一条极淡的高光边，模拟玻璃的反光轮廓
    static var panelEdge: NSColor { layer(0.12, 0.16) }
}

// MARK: - 面板

final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - 一行

final class MenuRowView: NSView {

    let entry: MenuEntry
    var onHover: ((MenuRowView) -> Void)?
    var onActivate: ((MenuRowView) -> Void)?

    private let highlight = NSView()
    private var tracking: NSTrackingArea?

    init(entry: MenuEntry) {
        self.entry = entry
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 7
        highlight.layer?.cornerCurve = .continuous
        highlight.layer?.backgroundColor = NSColor.clear.cgColor
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        let icon = NSImageView()
        icon.image = UIStatus.image(entry.icon, color: entry.tint, size: 13)
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let title = NSTextField(labelWithString: entry.title)
        title.font = .systemFont(ofSize: 13.5)
        title.textColor = entry.enabled ? .labelColor : .disabledControlTextColor
        title.isSelectable = false
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        // 右侧：开关项显示对勾，其余显示快捷键，两者互斥
        var trailing: NSView?
        if let on = entry.checked {
            let check = NSImageView()
            check.image = on
                ? UIStatus.image("checkmark", color: .controlAccentColor, size: 11)
                : nil
            check.translatesAutoresizingMaskIntoConstraints = false
            addSubview(check)
            NSLayoutConstraint.activate([
                check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
                check.centerYAnchor.constraint(equalTo: centerYAnchor),
                check.widthAnchor.constraint(equalToConstant: 13),
            ])
            trailing = check
        } else if !entry.key.isEmpty {
            let key = NSTextField(labelWithString: entry.key)
            key.font = .systemFont(ofSize: 12.5)
            key.textColor = .tertiaryLabelColor
            key.isSelectable = false
            key.translatesAutoresizingMaskIntoConstraints = false
            addSubview(key)
            NSLayoutConstraint.activate([
                key.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
                key.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            trailing = key
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: MenuTheme.rowH),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),

            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 38),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if let t = trailing {
            title.trailingAnchor.constraint(lessThanOrEqualTo: t.leadingAnchor, constant: -10).isActive = true
        } else {
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setHighlighted(_ on: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            highlight.animator().layer?.backgroundColor =
                (on ? MenuTheme.hoverFill : NSColor.clear).cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(self)
    }

    override func mouseUp(with event: NSEvent) {
        guard entry.enabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p) else { return }
        onActivate?(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

// MARK: - 分隔线

private final class Hairline: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = MenuTheme.hairline.cgColor
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 面板内容

final class MenuPanelView: NSView {

    private let stack = NSStackView()
    private(set) var rows: [MenuRowView] = []
    private var hovered: Int = -1

    var onClose: (() -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        appearanceRefresh()

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: MenuTheme.pad, left: MenuTheme.pad,
                                        bottom: MenuTheme.pad, right: MenuTheme.pad)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: MenuTheme.width),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceRefresh()
    }

    /// 背景与内描边都用动态色，明暗切换时重新取色
    private func appearanceRefresh() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            guard let layer = self?.layer else { return }
            layer.cornerRadius = MenuTheme.radius
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            layer.backgroundColor = MenuTheme.panelFill.cgColor
            layer.borderWidth = 1
            layer.borderColor = MenuTheme.panelEdge.cgColor
        }
    }

    var preferredSize: NSSize {
        layoutSubtreeIfNeeded()
        let h = ceil(stack.fittingSize.height)
        return NSSize(width: MenuTheme.width, height: max(h, 80))
    }

    // MARK: 构建

    func setModel(_ model: MenuModel) {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        rows.removeAll()
        hovered = -1

        stack.addArrangedSubview(makeHeader(model.header))

        for (gi, group) in model.groups.enumerated() {
            if gi > 0 {
                stack.addArrangedSubview(makeSpacer(6))
                stack.addArrangedSubview(makeDivider())
                stack.addArrangedSubview(makeSpacer(6))
            } else {
                stack.addArrangedSubview(makeSpacer(4))
                stack.addArrangedSubview(makeDivider())
                stack.addArrangedSubview(makeSpacer(4))
            }
            for e in group {
                let row = MenuRowView(entry: e)
                row.onHover = { [weak self] r in self?.hoverChanged(r) }
                row.onActivate = { [weak self] r in self?.activate(r) }
                rows.append(row)
                stack.addArrangedSubview(row)
            }
        }
    }

    private func makeHeader(_ h: MenuHeader) -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false

        let dot = NSImageView()
        dot.image = UIStatus.image(h.warn ? "exclamationmark.triangle.fill" : "circle.fill",
                                   color: h.warn ? .systemOrange : (h.on ? .systemGreen : .tertiaryLabelColor),
                                   size: h.warn ? 11 : 8)
        dot.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(dot)

        let title = NSTextField(labelWithString: h.title)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.isSelectable = false
        title.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(title)

        let detail = NSTextField(labelWithString: h.detail)
        detail.font = .systemFont(ofSize: 12.5)
        detail.textColor = .secondaryLabelColor
        detail.isSelectable = false
        detail.lineBreakMode = .byTruncatingTail
        detail.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(detail)

        let sub = NSTextField(labelWithString: "")
        sub.attributedStringValue = subLine(h.pills, note: h.note)
        sub.isSelectable = false
        sub.lineBreakMode = .byTruncatingTail
        sub.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(sub)

        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: 44),

            dot.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: box.centerYAnchor, constant: -9),
            dot.widthAnchor.constraint(equalToConstant: 12),

            title.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 24),
            title.centerYAnchor.constraint(equalTo: dot.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -10),

            detail.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 7),
            detail.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),

            sub.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 24),
            sub.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
        ])
        return box
    }

    /// 第二行：小图标 + 文字的轻量状态串（不做成标签块）
    private func subLine(_ pills: [MenuPill], note: String?) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11.5)
        let s = NSMutableAttributedString(string: "")
        for (i, p) in pills.enumerated() {
            if i > 0 {
                s.append(NSAttributedString(string: "    ", attributes: [.font: font]))
            }
            s.append(UIStatus.inline(p.icon, color: p.tint, font: font, size: 10))
            s.append(NSAttributedString(string: " " + p.text, attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        if let n = note, !n.isEmpty {
            s.append(NSAttributedString(string: "    " + n, attributes: [
                .font: font,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]))
        }
        return s
    }

    private func makeDivider() -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let line = Hairline()
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            line.topAnchor.constraint(equalTo: wrap.topAnchor),
        ])
        return wrap
    }

    private func makeSpacer(_ h: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }

    // MARK: 交互

    private func hoverChanged(_ row: MenuRowView) {
        guard let idx = rows.firstIndex(where: { $0 === row }) else { return }
        setHovered(idx)
    }

    private func setHovered(_ idx: Int) {
        guard idx != hovered else { return }
        if hovered >= 0, hovered < rows.count { rows[hovered].setHighlighted(false) }
        hovered = idx
        if hovered >= 0, hovered < rows.count {
            rows[hovered].setHighlighted(true)
        }
    }

    private func activate(_ row: MenuRowView) {
        row.entry.run()
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: move(1)            // ↓
        case 126: move(-1)           // ↑
        case 36, 76:                 // Return / Enter
            guard hovered >= 0, hovered < rows.count else { return }
            let e = rows[hovered].entry
            if e.enabled { e.run() }
        case 53:                     // Esc
            onClose?()
        default:
            super.keyDown(with: event)
        }
    }

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        var i = hovered
        repeat {
            i += delta
            if i < 0 { i = rows.count - 1 }
            if i >= rows.count { i = 0 }
        } while !rows[i].entry.enabled && i != hovered
        setHovered(i)
    }
}

// MARK: - 弹出控制

final class MenuPanelController {

    private var panel: MenuPanel?
    private var content: MenuPanelView?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var anchorRect: NSRect = .zero
    /// 面板刚被外部点击关闭时，避免同一次点击又把面板重新打开
    private var suppressUntil = Date.distantPast

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(anchor: NSRect, model: @autoclosure () -> MenuModel) {
        if isVisible {
            hide()
            return
        }
        guard Date() > suppressUntil else { return }
        show(anchor: anchor, model: model())
    }

    func show(anchor: NSRect, model: MenuModel) {
        close()

        let view = MenuPanelView()
        view.onClose = { [weak self] in self?.hide() }
        view.setModel(model)

        let size = view.preferredSize
        let p = MenuPanel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        p.contentView = view
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.animationBehavior = .utilityWindow

        anchorRect = anchor
        p.setFrame(frame(for: size), display: false)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(view)

        p.invalidateShadow()
        panel = p
        content = view
        installMonitors()
    }

    func update(_ model: MenuModel) {
        guard let p = panel, let v = content, p.isVisible else { return }
        v.setModel(model)
        let size = v.preferredSize
        p.setFrame(frame(for: size), display: true)
        p.makeFirstResponder(v)
    }

    private func frame(for size: NSSize) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchorRect.midX, y: anchorRect.midY)) }
            ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = anchorRect.midX - size.width / 2
        x = min(max(x, vis.minX + 8), vis.maxX - size.width - 8)

        // 状态栏图标在屏幕顶部：面板挂在按钮下沿
        var y = anchorRect.minY - size.height - 5
        if y < vis.minY + 8 { y = anchorRect.maxY + 5 }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func hide() {
        suppressUntil = Date().addingTimeInterval(0.15)
        close()
    }

    private func close() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        content = nil
    }

    private func installMonitors() {
        removeMonitors()

        // 全局：点到面板以外的任何窗口（含别的 App）都收起
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }

        // 本地：键盘、以及本 App 其它窗口上的点击
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
            guard let self, let p = self.panel, p.isVisible else { return e }
            if e.type == .keyDown { return e }   // 交给 firstResponder 处理
            if !p.frame.contains(NSEvent.mouseLocation) { self.hide() }
            return e
        }
    }

    private func removeMonitors() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
    }
}
