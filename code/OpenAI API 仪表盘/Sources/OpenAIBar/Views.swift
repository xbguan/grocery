import SwiftUI
import AppKit

// MARK: - 设计令牌
//
// 视觉方向：Liquid Glass（macOS 26 / iOS 26 起的材质语言）。
// 要点不是"加毛玻璃"，而是三层结构：底色渐变面 → 半透明玻璃卡片
// （顶部高光描边 + 底部收紧）→ 内容。卡片之间留出间隙，靠柔影分层，
// 而不是靠分隔线。

enum UI {
    static let panelWidth: CGFloat = 432
    static let hPad: CGFloat = 16
    static let cardRadius: CGFloat = 24
    static let gap: CGFloat = 9

    /// 「正在读取余额…」这一行很矮（≈40pt），而正常余额卡（标题+进度条+脚注）
    /// 约 100pt。读取态如果不撑高，加载结束切到余额卡时下方内容会突然上移一下。
    /// 这里给「读取中 / 读取失败」两张临时卡一个最小高度，和正常余额卡对齐；
    /// 正常余额卡、关闭态说明卡保持自然高度，不再被强行撑高，避免卡片底部多出空档。
    static let creditMinHeight: CGFloat = 104

    /// 头部与底栏的固定高度，用于给中间内容算可用空间
    static let headerHeight: CGFloat = 58
    static let footerHeight: CGFloat = 44

    /// 面板最大高度：跟随屏幕，别超出可视区
    static var maxPanelHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 12
    }

    /// 中间滚动区的最大高度
    static var maxBodyHeight: CGFloat {
        max(240, maxPanelHeight - headerHeight - footerHeight)
    }
}

extension Color {
    static func brand(_ s: ColorScheme) -> Color {
        s == .dark ? Color(nsColor: Brand.greenBright) : Color(nsColor: Brand.green)
    }
    /// 渐变用的深一档品牌色
    static func brandDeep(_ s: ColorScheme) -> Color {
        s == .dark ? Color(nsColor: Brand.green) : Color(nsColor: Brand.green).opacity(0.82)
    }
}

// MARK: - 玻璃材质

enum Glass {
    /// 卡片填充：上亮下暗，制造"玻璃片"的厚度
    static func fill(_ s: ColorScheme) -> LinearGradient {
        s == .dark
            ? LinearGradient(colors: [Color.white.opacity(0.115), Color.white.opacity(0.048)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color.white.opacity(0.82), Color.white.opacity(0.46)],
                             startPoint: .top, endPoint: .bottom)
    }

    /// 镜面描边：左上白亮、右下收暗，玻璃的高光边就在这条线上
    static func stroke(_ s: ColorScheme) -> LinearGradient {
        s == .dark
            ? LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.045)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color.white.opacity(0.98), Color.white.opacity(0.15)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 凹陷面（输入框、进度槽）
    static func inset(_ s: ColorScheme) -> LinearGradient {
        s == .dark
            ? LinearGradient(colors: [Color.black.opacity(0.30), Color.black.opacity(0.16)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color.black.opacity(0.055), Color.black.opacity(0.022)],
                             startPoint: .top, endPoint: .bottom)
    }

    static func hairline(_ s: ColorScheme) -> Color {
        s == .dark ? Color.white.opacity(0.085) : Color.black.opacity(0.055)
    }
}

private struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = UI.cardRadius
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Glass.fill(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Glass.stroke(scheme), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.42 : 0.07),
                    radius: elevated ? 16 : 9, x: 0, y: elevated ? 8 : 4)
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.22 : 0.035),
                    radius: 1, x: 0, y: 1)
    }
}

private extension View {
    func glassCard(radius: CGFloat = UI.cardRadius, elevated: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, elevated: elevated))
    }
}

/// 面板底色：双向渐变 + 顶部柔光，给玻璃卡片一个"透出来的底"
struct PanelBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(srgb: 0.137, 0.137, 0.153), Color(srgb: 0.071, 0.071, 0.082)]
                    : [Color(srgb: 0.965, 0.968, 0.976), Color(srgb: 0.902, 0.906, 0.922)],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Color.white.opacity(scheme == .dark ? 0.10 : 0.75), Color.clear],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

private extension Color {
    init(srgb r: Double, _ g: Double, _ b: Double) {
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// 测量中间内容高度，用来判断要不要滚动
private struct BodyHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - 按钮

/// 主按钮：品牌绿渐变胶囊 + 柔光投影
struct BrandButtonStyle: ButtonStyle {
    var scheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [Color.brand(scheme), Color.brandDeep(scheme)],
                                   startPoint: .top, endPoint: .bottom))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.34), lineWidth: 0.8))
            .shadow(color: Color.brand(scheme).opacity(0.34), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// 次要按钮：玻璃胶囊
struct GlassPillStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11.5 : 12, weight: .medium))
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.vertical, compact ? 6 : 7)
            .background(Capsule().fill(Glass.fill(scheme)))
            .overlay(Capsule().strokeBorder(Glass.stroke(scheme), lineWidth: 0.8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 圆形玻璃图标按钮
struct CircleIconButton: View {
    let system: String
    var help: String = ""
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(hover
                                  ? Color.primary.opacity(0.12)
                                  : (scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.62)))
                )
                .overlay(
                    Circle().strokeBorder(
                        Color.white.opacity(scheme == .dark ? 0.16 : 0.85), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// 小圆角标签（UTC、估算等）
/// 花费来源的时间范围切换
enum CostRange: String, CaseIterable {
    case today = "今日"
    case last7 = "近 7 天"
    case last30 = "近 30 天"
}

private struct Chip: View {
    let text: String
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(tint?.opacity(0.16)
                               ?? (scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)))
            )
            .foregroundStyle(tint ?? .secondary)
    }
}

// MARK: - 菜单栏

struct MenuBarLabel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: icon)
            Text(text)
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
        }
    }

    /// 图标永远是表盘，只换状态，不换成警告三角
    private var icon: NSImage {
        switch model.errorKind {
        case .some(.noKey): return MenuBarIcon.idle()
        case .some:         return MenuBarIcon.alert()
        case .none:         return MenuBarIcon.dial()
        }
    }

    private var text: String {
        if let snap = model.snapshot { return Fmt.money(snap.todayCost) }
        return "—"
    }
}

// MARK: - 主面板

struct MenuContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var bodyHeight: CGFloat = 0
    @State private var costRange: CostRange = .last7

    var body: some View {
        ZStack {
            PanelBackground()

            VStack(spacing: 0) {
                header
                middle
                footer
            }
        }
        .frame(width: UI.panelWidth)
        .tint(Color.brand(scheme))
        .onPreferenceChange(BodyHeightKey.self) { h in
            // 定高策略：只认第一次有效测量，定下来之后再也不跟内容走。
            //
            // 原因：MenuBarExtra 的窗口高度只能取整，而内容测量值常带小数；
            // 如果把测量值持续喂回 .frame(height:)，窗口与布局就会在取整之间
            // 反复拉锯，面板 1px 级持续抖动（上半区/下半区都可能，取决于哪块在变）。
            // 冻结后，内容再多也只会在滚动区内滚动，窗口尺寸恒定 → 结构上不可能抖。
            guard bodyHeight < 60, h > 120 else { return }
            bodyHeight = min(h.rounded(.up), UI.maxBodyHeight.rounded(.down))
        }
        .onChange(of: model.snapshot == nil) { _, _ in
            // 只有在「有数据 ↔ 无数据」这种离散切换时才重新定一次高度
            bodyHeight = 0
        }
        .transaction { $0.animation = nil }
        .onAppear {
            SettingsWindow.close()
            model.refreshCreditOnPanelOpen()
        }
    }

    /// 中间区域：内容自然撑开；超出屏幕可视高度时自己变成可滚动，
    /// 避免菜单栏窗口把底部（花费来源、底栏）裁掉。
    private var middle: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                if model.snapshot == nil, model.errorKind != nil {
                    errorState
                } else if let snap = model.snapshot {
                    VStack(spacing: UI.gap) {
                        hero(snap)
                        trend(snap)
                        kpis(snap)
                        balanceSection(snap)
                        if !snap.costBreakdown.isEmpty {
                            topItems(snap.costBreakdown, range: $costRange)
                        }
                    }
                    .padding(.horizontal, UI.hPad)
                    .padding(.bottom, 14)
                } else {
                    loadingState
                }
            }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: BodyHeightKey.self, value: g.size.height)
                }
            )
        }
        .frame(height: min(max(bodyHeight, 160), UI.maxBodyHeight.rounded(.down)))
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: LogoMark.image(size: 64))
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
                .shadow(color: Color.black.opacity(0.28), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                    .frame(width: 28, height: 28)
            } else {
                CircleIconButton(system: "arrow.clockwise", help: "立即刷新") {
                    Task { await model.refresh() }
                }
            }
        }
        .padding(.horizontal, UI.hPad)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var title: String {
        model.config.accountLabel.isEmpty ? "OpenAI API 仪表盘" : model.config.accountLabel
    }

    private var subtitle: String {
        if model.errorKind == .noKey { return "未配置 Admin Key" }
        if model.errorKind == .auth { return "Key 无效或权限不足" }
        return "Admin API · 组织级数据"
    }

    // MARK: 今日花费

    private func hero(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("今日花费")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Chip(text: "UTC")
                Spacer()
                Text("近 7 天 \(Fmt.money(snap.cost7))")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(Fmt.money(snap.todayCost))
                    .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(
                        LinearGradient(colors: [.primary, .primary.opacity(0.72)],
                                       startPoint: .top, endPoint: .bottom))

                Spacer(minLength: 8)

                Text("\(Fmt.tokens(snap.todayTokens)) tokens")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .glassCard(elevated: true)
    }

    // MARK: 14 天趋势（自绘，零值日也有可见底座）

    private func trend(_ snap: Snapshot) -> some View {
        let points = Array(snap.daily.suffix(14))
        let peak = points.map(\.cost).max() ?? 0
        let avg = points.isEmpty ? 0 : points.reduce(0) { $0 + $1.cost } / Double(points.count)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("近 14 天")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("日均 \(Fmt.money(avg))")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            DayBars(points: points, peak: peak)
                .frame(height: 64)

            HStack {
                Text(Fmt.dayLabel(points.first?.id ?? .now))
                Spacer()
                Text("UTC 自然日")
                Spacer()
                Text(Fmt.dayLabel(points.last?.id ?? .now))
            }
            .font(.system(size: 10.5).monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassCard()
    }

    // MARK: 三档汇总（三块独立玻璃片）

    private func kpis(_ snap: Snapshot) -> some View {
        HStack(spacing: 8) {
            kpiTile("今日", Fmt.money(snap.todayCost), "\(snap.todayRequests) 次请求")
            kpiTile("7 天", Fmt.money(snap.cost7), "\(Fmt.tokens(snap.tokens7)) tokens")
            kpiTile("30 天", Fmt.money(snap.cost30), "\(Fmt.tokens(snap.tokens30)) tokens")
        }
    }

    private func kpiTile(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(sub)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .glassCard(radius: 20)
    }

    // MARK: 额度

    /// 余额有五态，优先级：
    /// 有现值 > 开关关闭(未开启/刚关闭) > 登录已失效 > 从未登录 > 刷新失败 > 读取中
    @ViewBuilder
    private func balanceSection(_ snap: Snapshot) -> some View {
        Group {
            if let lc = model.liveCredit {
                balanceCard(liveInfo(lc), title: "API 余额")
            } else if !model.config.showCredit {
                // 状态 1（从未开启）与状态 2（从开启切回关闭）共用这张卡：
                // 关闭开关会同时清掉登录态，所以两者界面必须一致，不能残留上次读数。
                creditOffCard(snap)
            } else if model.creditState == .needsLogin {
                // 读到过 = 登录过期；从没读到 = 从未登录。动作相同，文案必须分开
                if model.config.hasConnectedCredit, let last = model.lastKnownCredit {
                    creditExpiredCard(last)
                } else {
                    creditLoginCard
                }
            } else if case .failed(let msg) = model.creditState {
                if let last = model.lastKnownCredit {
                    balanceCard(lastInfo(last), title: "API 余额", retry: true)
                } else {
                    creditFailedCard(msg)
                }
            } else {
                // showCredit 为真但状态还没落定：.off / .idle / .loading 都按读取中处理
                creditLoadingCard
            }
        }
    }

    /// 状态 1 / 2：开关关闭。说清「为什么 Key 拿不到余额」并给出唯一正确动作。
    private func creditOffCard(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("API 余额")
                    .font(.system(size: 12.5, weight: .semibold))
                Chip(text: "未开启")
                Spacer()
            }
            Text("官方暂未开放使用 ADMIN KEY 获取余额的能力。如需此功能，请到设置中开启「显示真实余额」，并登录 OpenAI 平台。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            creditLink("去设置开启", icon: "chevron.right") { openSettings() }
            if let b = snap.balance, let available = b.available {
                Text("估算额度：剩余 \(Fmt.money(available))" +
                     (b.limit.map { " / 上限 \(Fmt.money($0))" } ?? "") +
                     "（计费上限 − 本月已用，仅供参考）")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard()
    }

    /// 余额区统一的无边框动作按钮：只有文字 + 细箭头，无底色、无描边。
    /// 这块是「说明 + 一个动作」的结构，胶囊按钮太抢眼，会把说明压成配角。
    private func creditLink(_ title: String, icon: String? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(Color.brand(scheme))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func liveInfo(_ lc: LiveCredit) -> BalanceInfo {
        BalanceInfo(limit: lc.granted, used: lc.used, available: lc.available,
                    source: liveCreditSource(lc), isExact: true)
    }

    /// 刷新失败时的上次读数：数字照旧，但脚注说清是旧值，并给「重试」
    private func lastInfo(_ last: LiveCredit) -> BalanceInfo {
        BalanceInfo(limit: last.granted, used: last.used, available: last.available,
                    source: "OpenAI 平台会话 · 上次读数 \(Fmt.updatedLabel(last.at))（本次刷新失败）",
                    isExact: true)
    }

    /// 实时余额的说明行。刷新失败时保留上次读到的数字，但必须说明它已经旧了，
    /// 免得把一个几小时前的读数当成当前余额。
    private func liveCreditSource(_ lc: LiveCredit) -> String {
        let base = "OpenAI 平台会话 · 实时，\(Fmt.updatedLabel(lc.at))"
        if case .failed = model.creditState {
            return base + "（本次刷新失败，显示上次读数）"
        }
        return base
    }

    private var creditLoginCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("API 余额")
                    .font(.system(size: 12.5, weight: .semibold))
                Chip(text: "需要登录", tint: .orange)
                Spacer()
            }
            Text("官方暂未开放使用 ADMIN KEY 获取余额的能力。登录一次 OpenAI 平台即可显示真实余额；登录态只存在本机，App 不保存密码，也不保存 cookie 明文。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            creditLink("登录 OpenAI 平台", icon: "chevron.right") { model.loginForCredit() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard()
    }

    /// 登录过期：和「从未登录」必须长得不一样，否则用户不知道自己属于哪种
    private func creditExpiredCard(_ last: LiveCredit) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("API 余额")
                    .font(.system(size: 12.5, weight: .semibold))
                Chip(text: "登录已失效", tint: .orange)
                Spacer()
            }
            Text("平台登录态已过期，重新登录即可恢复。上次读到 \(Fmt.money(last.available)) · \(Fmt.updatedLabel(last.at))。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            creditLink("重新登录", icon: "chevron.right") { model.loginForCredit() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard()
    }

    private var creditLoadingCard: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small).scaleEffect(0.8)
            Text("正在读取余额…")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
        // 撑到和其它余额卡一样高并垂直居中，避免 loading 态只有一行、切状态时高度突变
        .frame(maxWidth: .infinity, minHeight: UI.creditMinHeight - 24, alignment: .center)
        .padding(12)
        .glassCard(radius: 20)
    }

    private func creditFailedCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("余额读取失败：\(message)")
                    .font(.system(size: 10.5))
                    .fixedSize(horizontal: false, vertical: true)
                creditLink("重试", icon: "arrow.clockwise") { model.retryCredit() }
            }
            Spacer(minLength: 0)
        }
        // 与「读取中」一样，撑到和正常余额卡接近的高度，避免状态切换时下方内容跳动
        .frame(maxWidth: .infinity, minHeight: UI.creditMinHeight - 24, alignment: .center)
        .padding(12)
        .glassCard(radius: 20)
    }

    private func balanceCard(_ balance: BalanceInfo, title: String = "API 额度", optIn: Bool = false, retry: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                if !balance.isExact {
                    Chip(text: "估算", tint: .orange)
                }
                Spacer()
                if let available = balance.available {
                    Text("剩余 \(Fmt.money(available))")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(available < 5 ? Color.red : Color.primary)
                }
            }

            if let limit = balance.limit, let used = balance.used, limit > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Glass.inset(scheme))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [used / limit > 0.85 ? Color.red.opacity(0.9) : Color.brand(scheme),
                                         used / limit > 0.85 ? Color.red.opacity(0.6) : Color.brandDeep(scheme)],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * min(1, used / limit)))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("已用 \(Fmt.money(used)) / 上限 \(Fmt.money(limit))")
                    Spacer()
                    Text("\(Int(min(100, used / limit * 100)))%")
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if optIn {
                HStack(spacing: 8) {
                    creditLink("读取真实余额", icon: "chevron.right") { model.loginForCredit() }
                    Text("需登录平台账号一次")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
            }

            if retry {
                HStack(spacing: 8) {
                    creditLink("重试", icon: "arrow.clockwise") { model.retryCredit() }
                    Text("上次读数仅供参照")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
            }

            Text(balance.source)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassCard()
    }

    // MARK: 花费来源

    private func topItems(_ breakdown: CostBreakdown, range: Binding<CostRange>) -> some View {
        let items: [ItemCost] = {
            switch range.wrappedValue {
            case .today: return breakdown.today
            case .last7: return breakdown.last7
            case .last30: return breakdown.last30
            }
        }()
        let total = max(items.reduce(0) { $0 + $1.cost }, 0.0001)
        // 进度条按「相对最大项」铺开：最大项填满轨道，其余按比例，避免按总和算时
        // 每条都只占轨道一小截、后半段空跑显得拖沓。
        let maxCost = items.first?.cost ?? total
        return VStack(alignment: .leading, spacing: 10) {
            // 标题行：标题 + 无边框时间切换 + 合计（前 5 项之和）
            HStack(alignment: .center, spacing: 12) {
                Text("花费来源")
                    .font(.system(size: 12.5, weight: .semibold))
                HStack(spacing: 10) {
                    ForEach(CostRange.allCases, id: \.self) { r in
                        rangeChip(r, selected: range.wrappedValue == r) {
                            range.wrappedValue = r
                        }
                    }
                }
                Spacer()
                Text(Fmt.money(total))
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text("该时间段暂无花费")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 9) {
                    ForEach(items) { item in
                        VStack(spacing: 5) {
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .font(.system(size: 12.5))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 6)
                                Text(Fmt.money(item.cost))
                                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            }
                            // 进度条与 token/请求数同一行：轨道占满 token 左侧空间、顶到数字前，
                            // 右侧不再空跑。填充按「相对最大项」比例，用内层 GeometryReader 量轨道实际宽度。
                            HStack(spacing: 8) {
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Glass.inset(scheme))
                                    GeometryReader { barGeo in
                                        Capsule()
                                            .fill(LinearGradient(
                                                colors: [Color.brand(scheme).opacity(0.85),
                                                         Color.brand(scheme).opacity(0.42)],
                                                startPoint: .leading, endPoint: .trailing))
                                            .frame(width: max(3, barGeo.size.width * item.cost / maxCost))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 4)

                                Text(itemSubtitle(item))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            .frame(height: 11)
                        }
                    }
                }
            }

            // 右上角金额是「前 5 项」之和，不是当前范围全部花费，必须说清楚，
            // 否则一个数字容易被当成整个范围的总花费。
            Text("仅显示花费最高的前 5 项，右上角为这 5 项之和")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassCard()
    }

    /// 时间范围切换：无边框纯文字，选中品牌色加粗，未选中灰色。
    private func rangeChip(_ range: CostRange, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(range.rawValue)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.brand(scheme) : .secondary)
        }
        .buttonStyle(.plain)
    }

    /// 每个花费项的次要信息：token 量（K/M/B 缩写）+ 请求数，纯数字、无单位词。
    /// 图片类模型 token 为 0，只显示请求数。
    private func itemSubtitle(_ item: ItemCost) -> String {
        if item.tokens > 0 {
            return "\(Fmt.tokens(item.tokens)) · \(Fmt.tokens(item.requests))"
        }
        return "\(Fmt.tokens(item.requests))"
    }

    // MARK: 空 / 错误状态

    private var errorState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 66, height: 66)
                Circle()
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.18 : 0.7), lineWidth: 1)
                    .frame(width: 66, height: 66)
                Image(systemName: iconName)
                    .font(.system(size: 27, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            }
            .shadow(color: Color.orange.opacity(0.18), radius: 14, y: 6)
            .padding(.top, 10)

            VStack(spacing: 7) {
                Text(errorTitle)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                // 副标题只放提示，不再重复标题（之前两行字一模一样）
                if let hint = model.errorHint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
                if model.errorKind != .noKey, let msg = model.errorText {
                    Text(msg)
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
            }

            primaryAction

            if model.errorKind == .noKey || model.errorKind == .auth {
                Link(destination: URL(string: "https://platform.openai.com/settings/organization/admin-keys")!) {
                    Text("打开 OpenAI 后台创建 Admin Key")
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
    }

    private var iconName: String {
        switch model.errorKind {
        case .some(.noKey): return "key.horizontal.fill"
        case .some(.auth):  return "lock.fill"
        default:            return "wifi.slash"
        }
    }

    private var errorTitle: String {
        switch model.errorKind {
        case .some(.noKey): return "还没有配置 Admin Key"
        case .some(.auth):  return "Key 未被接受"
        default:            return "读取数据失败"
        }
    }

    /// 一个按钮，只给「此刻唯一该做的事」，不再和底部的「设置」重复
    @ViewBuilder
    private var primaryAction: some View {
        switch model.errorKind {
        case .some(.noKey):
            Button("填入 Admin Key") { openSettings() }
                .buttonStyle(BrandButtonStyle(scheme: scheme))
        case .some(.auth):
            Button("重新填写 Key") { openSettings() }
                .buttonStyle(BrandButtonStyle(scheme: scheme))
        case .some:
            Button {
                Task { await model.refresh() }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(BrandButtonStyle(scheme: scheme))
        case .none:
            EmptyView()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("正在读取用量数据…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    // MARK: 底部

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Glass.hairline(scheme))
                .frame(height: 1)

            HStack(spacing: 14) {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .font(.system(size: 11.5, weight: .medium))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("设置 Admin Key 与刷新间隔")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 11.5, weight: .medium))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("退出 OpenAI API 仪表盘")
            }
            .padding(.horizontal, UI.hPad)
            .padding(.vertical, 11)
        }
    }

    private var statusText: String {
        if model.isLoading && model.snapshot == nil { return "正在更新…" }
        guard let snap = model.snapshot else { return "尚未加载" }
        return Fmt.updatedLabel(snap.fetchedAt)
    }

    private func openSettings() {
        // 先收起菜单面板，再开设置窗口：两个窗口不该同时浮在屏幕上
        MenuBarPanel.closeIfOpen()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            SettingsWindow.show(model: model)
        }
    }
}

// MARK: - 14 天柱状图（自绘）

private struct DayBars: View {
    let points: [DayPoint]
    let peak: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let n = max(points.count, 1)
            let slot = geo.size.width / CGFloat(n)
            let barW = min(14, max(4, slot * 0.58))
            let maxV = max(peak, 0.0001)
            let lastID = points.last?.id

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(points) { p in
                    let ratio = p.cost / maxV
                    let h = p.cost <= 0 ? 3 : max(5, geo.size.height * ratio)
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: barW / 2, style: .continuous)
                            .fill(fill(for: p, isLast: p.id == lastID))
                            .frame(width: barW, height: h)
                            .shadow(color: p.id == lastID && p.cost > 0
                                    ? Color.brand(scheme).opacity(0.45) : .clear,
                                    radius: 7, x: 0, y: 2)
                    }
                    .frame(width: slot)
                    .help("\(Fmt.dayLabel(p.id)) · \(Fmt.money(p.cost))")
                }
            }
        }
    }

    private func fill(for p: DayPoint, isLast: Bool) -> LinearGradient {
        if p.cost <= 0 {
            return LinearGradient(colors: [Color.primary.opacity(0.10), Color.primary.opacity(0.06)],
                                  startPoint: .top, endPoint: .bottom)
        }
        let top = isLast ? Color.brand(scheme) : Color.brand(scheme).opacity(0.45)
        let bottom = isLast ? Color.brandDeep(scheme) : Color.brand(scheme).opacity(0.22)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    @State private var keyDraft = ""
    @State private var projectDraft = ""
    @State private var labelDraft = ""
    @State private var refreshDraft = 5
    @State private var creditDraft = false
    @State private var showKey = false
    @State private var testMessage: String?
    @State private var testOK = false
    @State private var isTesting = false
    @State private var didInit = false
    @FocusState private var focusedField: Field?

    private enum Field { case key, project, label }

    var body: some View {
        ZStack {
            PanelBackground()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 12) {
                        keySection
                        creditSection
                        projectSection
                        displaySection
                        aboutSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }

                footerBar
            }
        }
        .frame(width: 560, height: 720)
        .tint(Color.brand(scheme))
        .onAppear(perform: loadDrafts)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 13) {
            Image(nsImage: LogoMark.image(size: 84))
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .shadow(color: Color.black.opacity(0.3), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("OpenAI API 仪表盘")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("组织级用量与花费 · 数据来自 API 平台，与 ChatGPT 订阅无关")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    // MARK: 各分区

    private var keySection: some View {
        section("Admin API Key", icon: "key.horizontal") {
            HStack(spacing: 8) {
                Group {
                    if showKey {
                        TextField("sk-admin-…", text: $keyDraft)
                            .focused($focusedField, equals: .key)
                    } else {
                        SecureField("sk-admin-…", text: $keyDraft)
                            .focused($focusedField, equals: .key)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(inputBG)
                .overlay(inputBorder)

                Button(showKey ? "隐藏" : "显示") { showKey.toggle() }
                    .buttonStyle(GlassPillStyle(compact: true))
                    .frame(width: 46)
            }

            Text("必须以 sk-admin- 开头。组织用量与成本接口不接受普通项目 Key。保存后写入 macOS 钥匙串，配置文件里不含 Key。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let fp = keyFingerprint {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.brand(scheme))
                    Text(fp)
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("测试连接") { runTest() }
                    .buttonStyle(GlassPillStyle(compact: true))
                    .disabled(isTesting || keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("清除 Key") { clearKey() }
                    .buttonStyle(GlassPillStyle(compact: true))
                    .foregroundStyle(.secondary)
                    .disabled(keyDraft.isEmpty)

                if isTesting {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }

            if let msg = testMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: testOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                    Text(msg)
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .foregroundStyle(testOK ? Color.brand(scheme) : Color.orange)
            }
        }
    }

    /// 实时余额：官方 API 拿不到，只能借平台登录态
    private var creditSection: some View {
        section("API 余额（实时）", icon: "creditcard") {
            Toggle(isOn: $creditDraft) {
                Text("显示真实余额")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Text("官方暂未开放用 ADMIN KEY 读取余额的接口（任何 Key 请求它都返回 403），所以这部分与 Key 无关：开启后 App 借本机平台登录态读取「剩余额度」，登录态存在 App 自己的 WebKit 容器里，不保存密码、不保存 cookie 明文。\n注意：关闭开关会同时清空本机登录态（等于退出登录），下次开启需要重新登录一次。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(model.liveCredit == nil ? "登录 OpenAI 平台" : "重新登录") {
                    creditDraft = true
                    model.loginForCredit()
                }
                .buttonStyle(GlassPillStyle(compact: true))

                Button("退出登录") { model.clearCreditLogin() }
                    .buttonStyle(GlassPillStyle(compact: true))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(creditStatusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var creditStatusText: String {
        if let lc = model.liveCredit {
            return "已读取 \(Fmt.money(lc.available)) · \(Fmt.updatedLabel(lc.at))"
        }
        switch model.creditState {
        case .needsLogin: return model.config.hasConnectedCredit ? "登录已失效" : "需要登录"
        case .loading:    return "读取中…"
        case .failed(let m): return "失败：\(m)"
        case .ready: return "已读取"
        case .off, .idle: return "尚未读取"
        }
    }

    private var projectSection: some View {
        section("项目（可选）", icon: "square.stack.3d.up") {
            TextField("proj_…", text: $projectDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(inputBG)
                .overlay(inputBorder)
                .focused($focusedField, equals: .project)
            Text("留空统计整个组织；填写后只统计该项目。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var displaySection: some View {
        section("显示", icon: "slider.horizontal.3") {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("菜单栏备注名")
                        .font(.system(size: 11.5, weight: .medium))
                    TextField("OpenAI API 仪表盘", text: $labelDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(inputBG)
                        .overlay(inputBorder)
                        .focused($focusedField, equals: .label)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("自动刷新")
                        .font(.system(size: 11.5, weight: .medium))
                    Picker("", selection: $refreshDraft) {
                        Text("1 分钟").tag(1)
                        Text("5 分钟").tag(5)
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("60 分钟").tag(60)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var aboutSection: some View {
        section("数据来源", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 5) {
                Text("· 花费与用量来自 API 平台的 `/v1/organization/*` 组织级接口，按 UTC 自然日统计。")
                Text("· 余额没有对 API Key 开放的接口（服务器明确要求浏览器会话）。在设置里开启「实时余额」后，App 借本机平台登录态读取，数据不出本机。")
                Text("· Key 保存在 macOS 钥匙串（「钥匙串访问」搜 OpenAI API 仪表盘），不写入任何文件。")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Glass.hairline(scheme))
                .frame(height: 1)

            HStack(spacing: 12) {
                Link(destination: URL(string: "https://platform.openai.com/settings/organization/api-keys")!) {
                    Text("打开 OpenAI 后台")
                        .font(.system(size: 11.5, weight: .medium))
                }
                Spacer()
                Text(appVersion)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Button("保存") { saveAndClose() }
                    .buttonStyle(BrandButtonStyle(scheme: scheme))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
        }
    }

    // MARK: 零件

    private var inputBG: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Glass.inset(scheme))
    }

    private var inputBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Glass.stroke(scheme), lineWidth: 1)
    }

    private func section<Content: View>(_ title: String,
                                        icon: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.brand(scheme))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(radius: 20)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return v.isEmpty ? "" : "v\(v)"
    }

    private var keyFingerprint: String? {
        let t = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 16 else { return nil }
        return "\(t.prefix(12))…\(t.suffix(4)) · \(t.count) 字符"
    }

    // MARK: 动作

    private func loadDrafts() {
        guard !didInit else { return }
        didInit = true
        keyDraft = model.config.adminKey
        projectDraft = model.config.projectID
        labelDraft = model.config.accountLabel
        refreshDraft = model.config.refreshMinutes
        creditDraft = model.config.showCredit
    }

    /// 保存即完成：写配置 → 刷新数据 → 关闭设置窗口
    private func saveAndClose() {
        model.update { cfg in
            cfg.adminKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            cfg.projectID = projectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            cfg.accountLabel = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            cfg.refreshMinutes = refreshDraft
            cfg.showCredit = creditDraft
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
        SettingsWindow.close()
    }

    private func clearKey() {
        keyDraft = ""
        testOK = false
        testMessage = "已清除，钥匙串里的 Key 已删除"
        model.clearKey()
    }

    private func runTest() {
        isTesting = true
        testMessage = nil
        Task {
            let (ok, msg) = await model.testConnection(keyDraft)
            await MainActor.run {
                testOK = ok
                testMessage = msg
                isTesting = false
            }
        }
    }
}
