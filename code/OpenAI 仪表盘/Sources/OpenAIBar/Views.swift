import SwiftUI
import AppKit

// MARK: - 设计令牌
//
// 视觉方向：Liquid Glass（macOS 26 / iOS 26 起的材质语言）。
// 要点不是"加毛玻璃"，而是三层结构：底色渐变面 → 半透明玻璃卡片
// （顶部高光描边 + 底部收紧）→ 内容。卡片之间留出间隙，靠柔影分层，
// 而不是靠分隔线。

private let adminKeysURL = URL(string: "https://platform.openai.com/settings/organization/admin-keys")!

enum UI {
    static let panelWidth: CGFloat = 708
    static let sidebarWidth: CGFloat = 202
    static let hPad: CGFloat = 16
    static let cardRadius: CGFloat = 24
    static let gap: CGFloat = 9

    /// 「正在读取余额…」这一行很矮（≈40pt），而正常余额卡（标题+进度条+脚注）
    /// 约 100pt。读取态如果不撑高，加载结束切到余额卡时下方内容会突然上移一下。
    /// 这里给「读取中 / 读取失败」两张临时卡一个最小高度，和正常余额卡对齐；
    /// 正常余额卡、关闭态说明卡保持自然高度，不再被强行撑高，避免卡片底部多出空档。
    static let creditMinHeight: CGFloat = 104

    static var panelHeight: CGFloat {
        min(690, (NSScreen.main?.visibleFrame.height ?? 900) - 16)
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

enum TextTone {
    static func secondary(_ s: ColorScheme) -> Color {
        s == .dark ? Color.white.opacity(0.78) : Color(nsColor: .secondaryLabelColor)
    }

    static func tertiary(_ s: ColorScheme) -> Color {
        s == .dark ? Color.white.opacity(0.62) : Color(nsColor: .tertiaryLabelColor)
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
        let dark = scheme == .dark
        let fill = LinearGradient(colors: [
            Color.white.opacity(dark ? 0.065 : 0.79),
            Color.white.opacity(dark ? 0.055 : 0.63)
        ], startPoint: .top, endPoint: .bottom)
        let edge = LinearGradient(colors: [
            dark ? Color.white.opacity(0.055) : Color.white.opacity(0.50),
            dark ? Color.white.opacity(0.035) : Color.black.opacity(0.035)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)

        return content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(edge, lineWidth: 1)
            )
            .compositingGroup()
            .shadow(color: Color.black.opacity(dark ? 0.20 : 0.05),
                    radius: elevated ? 10 : 6, x: 0, y: elevated ? 4 : 2)
            .shadow(color: Color.black.opacity(dark ? 0.09 : 0.025),
                    radius: 1, x: 0, y: 1)
    }
}

extension View {
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
                .opacity(0.55)
            RadialGradient(
                colors: [Color.white.opacity(scheme == .dark ? 0.10 : 0.75), Color.clear],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadius: 0, endRadius: 420)
        }
        .background(.regularMaterial)
        .ignoresSafeArea()
    }
}

private extension Color {
    init(srgb r: Double, _ g: Double, _ b: Double) {
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
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
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11.5 : 12, weight: .medium))
            .padding(.horizontal, compact ? 11 : 14)
            .padding(.vertical, compact ? 6 : 7)
            .background(Capsule().fill(Glass.fill(scheme)))
            .overlay(Capsule().strokeBorder(Glass.stroke(scheme), lineWidth: 0.8))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.48)
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
        .foregroundStyle(TextTone.secondary(scheme))
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
            .foregroundStyle(tint ?? TextTone.secondary(scheme))
    }
}

// MARK: - 主面板

struct MenuContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    enum Page: String {
        case usage = "API 用量"
        case subscription = "ChatGPT 订阅"
        case settings = "设置"
    }

    @State private var usingKeyboard = false
    @State private var navigationMonitor: Any?
    @State private var page: Page
    @State private var showingPlanInfo = false
    @State private var costRange: CostRange = .last7

    init(initialPage: Page = .usage) {
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                switch page {
                case .usage:
                    if UI.panelHeight < 650 {
                        ScrollView { usageContent }
                    } else {
                        usageContent
                    }
                case .settings:
                    SettingsForm { page = .usage }
                case .subscription:
                    ScrollView { subscription }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: UI.panelWidth, height: UI.panelHeight)
        .background(PanelBackground())
        .tint(Color.brand(scheme))
        .onAppear {
            model.refreshCreditOnPanelOpen()
            guard navigationMonitor == nil else { return }
            usingKeyboard = false
            navigationMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
                if event.type == .leftMouseDown { usingKeyboard = false }
                else if event.keyCode == 48 { usingKeyboard = true } // Tab or Shift-Tab
                return event
            }
        }
        .onDisappear {
            if let navigationMonitor { NSEvent.removeMonitor(navigationMonitor) }
            navigationMonitor = nil
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: LogoMark.image(size: 64))
                    .resizable().frame(width: 28, height: 28)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1).help(title)
                Spacer(minLength: 0)
                if model.isLoading || model.creditState == .loading || model.subscriptionLoading {
                    ProgressView().controlSize(.small).frame(width: 28, height: 28)
                        .accessibilityLabel("正在刷新")
                } else {
                    CircleIconButton(system: "arrow.clockwise", help: "刷新全部数据") {
                        Task { await model.refresh(manual: true) }
                    }
                    .accessibilityLabel("刷新全部数据")
                    .focusEffectDisabled(!usingKeyboard)
                }
            }
            .padding(.bottom, 12)
            navButton(.usage, icon: "chevron.left.forwardslash.chevron.right")
            navButton(.subscription, icon: "person")
            Spacer()
            Divider().padding(.bottom, 2)
            HStack(spacing: 0) {
                Button { page = .settings } label: {
                    sidebarActionLabel("设置", icon: "gearshape")
                }
                    .foregroundStyle(page == .settings ? Color.brand(scheme) : .primary)
                    .accessibilityAddTraits(page == .settings ? .isSelected : [])
                Divider().frame(height: 14)
                Button { NSApplication.shared.terminate(nil) } label: {
                    sidebarActionLabel("退出", icon: "rectangle.portrait.and.arrow.right")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: UI.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Glass.inset(scheme))
    }

    private func sidebarActionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(title)
        }
        .font(.system(size: 13))
        .fixedSize()
        .frame(maxWidth: .infinity, minHeight: 30)
        .contentShape(Rectangle())
    }

    private func navButton(_ destination: Page, icon: String) -> some View {
        let selected = page == destination
        return Button { page = destination } label: {
            Label {
                Text(destination.rawValue)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 20)
            }
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.brand(scheme).opacity(0.20) : .clear,
                            in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled(!usingKeyboard)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var subscription: some View {
        VStack(alignment: .leading, spacing: UI.gap) {
            if let data = model.subscription {
                subscriptionSummary(data)
                SubscriptionAnalyticsView(data: data)
            }
            if let message = subscriptionMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(TextTone.secondary(scheme))
            }
            if model.subscription == nil {
                Button("订阅设置") { page = .settings }
                    .buttonStyle(GlassPillStyle(compact: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UI.hPad)
        .padding(.bottom, 12)
    }

    private var subscriptionMessage: String? {
        if model.subscriptionLoginInProgress { return "等待 ChatGPT 登录…" }
        if let error = model.subscriptionError { return error }
        if !model.config.hasConnectedSubscription { return "在设置中登录 ChatGPT，可读取套餐和用量分析。" }
        if model.subscriptionLoading { return "正在读取订阅…" }
        return nil
    }

    private func subscriptionSummary(_ data: SubscriptionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            weeklyQuota(data)
            Divider()
            resetCredits(data)
        }
        .padding(16).glassCard()
    }

    private func weeklyQuota(_ data: SubscriptionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Codex 本周剩余额度").fixedSize()
                Spacer()
                if let masked = data.maskedEmail, let email = data.email {
                    Text(verbatim: masked)
                        .lineLimit(1).truncationMode(.middle)
                        .font(.system(size: 11))
                        .help(email)
                }
            }
            .font(.callout)
            .foregroundStyle(TextTone.secondary(scheme))

            Text(data.remainingPercent.map { "\($0)%" } ?? "—")
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
            if let percent = data.remainingPercent {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule().fill(Color.brand(scheme))
                            .frame(width: geometry.size.width * CGFloat(percent) / 100)
                    }
                }
                .frame(height: 6)
                .accessibilityRepresentation {
                    ProgressView("Codex 本周剩余额度", value: Double(percent), total: 100)
                }
            }
            HStack {
                Text("下次周重置")
                Text(data.weeklyReset?.formatted(date: .abbreviated, time: .shortened) ?? "未取得")
            }
            .font(.system(size: 12))
            .foregroundStyle(TextTone.secondary(scheme))
        }
    }

    private func resetCredits(_ data: SubscriptionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("可用重置次数")
                Spacer()
                Text(data.resetCredits.map { "\($0) 次" } ?? "未取得")
            }
            .font(.headline)
            ForEach(data.resetCreditDetails) { credit in
                Divider()
                HStack {
                    Text(credit.expiresAt.map { "\($0.formatted(date: .abbreviated, time: .shortened)) 到期" } ?? "到期时间未知")
                    Spacer()
                    Text("1 次")
                }
                .font(.system(size: 12).monospacedDigit())
            }
            if let count = data.resetCredits, count > data.resetCreditDetails.count {
                Text("另有 \(count - data.resetCreditDetails.count) 次未取得到期时间")
                    .font(.system(size: 11))
                    .foregroundStyle(TextTone.secondary(scheme))
            }
        }
    }

    private func planBadge(_ data: SubscriptionSnapshot) -> some View {
        HStack(spacing: 6) {
            Chip(text: data.displayPlan ?? "未确认")
            Button { showingPlanInfo.toggle() } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("套餐说明")
            .popover(isPresented: $showingPlanInfo) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("来源：本应用登录的 ChatGPT 账号")
                    if let plan = data.plan { Text("Codex 账号标识：\(plan)") }
                    if data.displayPlan == "Pro" { Text("具体 Pro 档位以 ChatGPT 为准。") }
                }
                .font(.system(size: 11))
                .padding(12)
            }
        }
    }

    @ViewBuilder private var usageContent: some View {
        if model.snapshot == nil, model.errorKind != nil {
            errorState
        } else if let snap = model.snapshot {
            VStack(spacing: UI.gap) {
                kpis(snap)
                trend(snap)
                balanceSection(snap)
                if !snap.costBreakdown.isEmpty {
                    topItems(snap.costBreakdown, range: $costRange)
                }
            }
            .padding(.horizontal, UI.hPad)
            .padding(.bottom, 12)
        } else {
            loadingState
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.rawValue)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                if page == .usage {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(TextTone.secondary(scheme))
                }
            }
            if page == .subscription, let data = model.subscription {
                planBadge(data)
            }
            Spacer(minLength: 8)
            if page != .settings {
                pageUpdateLabel
                    .font(.system(size: 11))
                    .foregroundStyle(TextTone.secondary(scheme))
            }
        }
        .padding(.horizontal, UI.hPad)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var pageUpdateLabel: some View {
        let isUsage = page == .usage
        if let updated = isUsage ? model.snapshot?.fetchedAt : model.lastSubscriptionUpdate {
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                Text(Fmt.updatedLabel(updated, relativeTo: clock.date))
                    .monospacedDigit()
            }
            .help(updated.formatted(date: .abbreviated, time: .standard))
        } else {
            Text((isUsage ? model.isLoading : model.subscriptionLoading) ? "正在更新…" : "尚未更新")
        }
    }

    private var title: String {
        model.config.accountLabel.isEmpty ? "OpenAI 仪表盘" : model.config.accountLabel
    }

    private var subtitle: String {
        if model.errorKind == .noKey { return model.config.credentialReadFailed ? "凭据读取失败" : "未配置 Admin Key" }
        if model.errorKind == .auth { return "Key 无效或权限不足" }
        return "Admin API · 组织级数据"
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
                    .foregroundStyle(TextTone.secondary(scheme))
            }

            DayBars(points: points, peak: peak)
                .frame(height: 52)

            HStack {
                Text(Fmt.dayLabel(points.first?.id ?? .now))
                Spacer()
                Text("UTC 自然日")
                Spacer()
                Text(Fmt.dayLabel(points.last?.id ?? .now))
            }
            .font(.system(size: 10.5).monospacedDigit())
            .foregroundStyle(TextTone.tertiary(scheme))
        }
        .padding(12)
        .glassCard()
    }

    // MARK: 三档汇总（三块独立玻璃片）

    private func kpis(_ snap: Snapshot) -> some View {
        HStack(spacing: 8) {
            kpiTile("今日 · UTC", Fmt.money(snap.todayCost), "\(Fmt.tokens(snap.todayTokens)) tokens · \(Fmt.tokens(snap.todayRequests)) 次请求")
            kpiTile("7 天", Fmt.money(snap.cost7), "\(Fmt.tokens(snap.tokens7)) tokens")
            kpiTile("30 天", Fmt.money(snap.cost30), "\(Fmt.tokens(snap.tokens30)) tokens")
        }
    }

    private func kpiTile(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(TextTone.secondary(scheme))
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(sub)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(TextTone.tertiary(scheme))
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
                balanceCard(liveInfo(lc), title: "API 余额", showExpiry: true)
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
            Text("官方暂未开放使用 ADMIN KEY 获取余额的能力。如需此功能，请到设置中开启「显示实时余额」，并登录 OpenAI 平台。")
                .font(.system(size: 10.5))
                .foregroundStyle(TextTone.secondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            creditLink("去设置开启", icon: "chevron.right") { page = .settings }
            if let b = snap.balance, let available = b.available {
                Text("估算额度：剩余 \(Fmt.money(available))" +
                     (b.limit.map { " / 上限 \(Fmt.money($0))" } ?? "") +
                     "（计费上限 − 本月已用，仅供参考）")
                    .font(.system(size: 9.5))
                    .foregroundStyle(TextTone.tertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
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
                    source: liveCreditSource(lc), isExact: true, expiry: lc.expiry)
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
                .foregroundStyle(TextTone.secondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            creditLink("登录 OpenAI 平台", icon: "chevron.right") { model.loginForCredit() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
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
                .foregroundStyle(TextTone.secondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            creditLink("重新登录", icon: "chevron.right") { model.loginForCredit() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard()
    }

    private var creditLoadingCard: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small).scaleEffect(0.8)
            Text("正在读取余额…")
                .font(.system(size: 10.5))
                .foregroundStyle(TextTone.secondary(scheme))
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

    private func balanceCard(_ balance: BalanceInfo, title: String = "API 额度", optIn: Bool = false,
                             retry: Bool = false, showExpiry: Bool = false) -> some View {
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
                if showExpiry {
                    Text(balance.expiry.map { "最近到期 \($0.countdown(asOf: .now))" } ?? "效期未取得")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(balance.expiry == nil ? TextTone.tertiary(scheme) : Color.brand(scheme))
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
                .foregroundStyle(TextTone.secondary(scheme))
            }

            if optIn {
                HStack(spacing: 8) {
                    creditLink("读取真实余额", icon: "chevron.right") { model.loginForCredit() }
                    Text("需登录平台账号一次")
                        .font(.system(size: 10.5))
                        .foregroundStyle(TextTone.tertiary(scheme))
                    Spacer(minLength: 0)
                }
            }

            if showExpiry, let expiry = balance.expiry {
                HStack {
                    Text("到期：\(expiry.date.formatted(date: .numeric, time: .shortened))")
                    Spacer()
                    Text("该笔剩余 \(Fmt.money(expiry.remaining))")
                }
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(TextTone.secondary(scheme))
            }

            if retry {
                HStack(spacing: 8) {
                    creditLink("重试", icon: "arrow.clockwise") { model.retryCredit() }
                    Text("上次读数仅供参照")
                        .font(.system(size: 10.5))
                        .foregroundStyle(TextTone.tertiary(scheme))
                    Spacer(minLength: 0)
                }
            }

            Text(balance.source)
                .font(.system(size: 10.5))
                .foregroundStyle(TextTone.tertiary(scheme))
        }
        .padding(12)
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
        // 进度条占比分母：当前范围的「全部花费总额」（含未显示进 Top 5 的零星项），
        // 让每项长度反映它在总花费里的真实占比，而不是相对最高项的倍数。
        let fullTotal: Double = {
            switch range.wrappedValue {
            case .today: return breakdown.todayTotal
            case .last7: return breakdown.last7Total
            case .last30: return breakdown.last30Total
            }
        }()
        let denominator = max(fullTotal, total, 0.0001)
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
                    .foregroundStyle(TextTone.secondary(scheme))
            }

            if items.isEmpty {
                Text("该时间段暂无花费")
                    .font(.system(size: 11.5))
                    .foregroundStyle(TextTone.tertiary(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
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
                            // 右侧不再空跑。填充按「该项 ÷ 全部花费总额」比例，用内层 GeometryReader 量轨道实际宽度。
                            HStack(spacing: 8) {
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Glass.inset(scheme))
                                    GeometryReader { barGeo in
                                        Capsule()
                                            .fill(LinearGradient(
                                                colors: [Color.brand(scheme).opacity(0.85),
                                                         Color.brand(scheme).opacity(0.42)],
                                                startPoint: .leading, endPoint: .trailing))
                                            .frame(width: max(3, barGeo.size.width * item.cost / denominator))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 4)

                                Text(itemSubtitle(item))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(TextTone.tertiary(scheme))
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
                .foregroundStyle(TextTone.tertiary(scheme))
        }
        .padding(12)
        .glassCard()
    }

    /// 时间范围切换：无边框纯文字，选中品牌色加粗，未选中灰色。
    private func rangeChip(_ range: CostRange, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(range.rawValue)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.brand(scheme) : TextTone.secondary(scheme))
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
                        .foregroundStyle(TextTone.secondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
                if model.errorKind != .noKey, let msg = model.errorText {
                    Text(msg)
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(TextTone.tertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
            }

            primaryAction

            if model.errorKind == .noKey || model.errorKind == .auth {
                Link(destination: adminKeysURL) {
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
        case .some(.noKey): return model.config.credentialReadFailed ? "无法读取已保存的 Admin Key" : "还没有配置 Admin Key"
        case .some(.auth):  return "Key 未被接受"
        default:            return "读取数据失败"
        }
    }

    /// 一个按钮，只给「此刻唯一该做的事」，不再和底部的「设置」重复
    @ViewBuilder
    private var primaryAction: some View {
        switch model.errorKind {
        case .some(.noKey):
            Button("填入 Admin Key") { page = .settings }
                .buttonStyle(BrandButtonStyle(scheme: scheme))
        case .some(.auth):
            Button("重新填写 Key") { page = .settings }
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
                .foregroundStyle(TextTone.secondary(scheme))
        }
        .padding(40)
        .frame(maxWidth: .infinity)
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

private struct SettingsFieldSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var focused = false

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Glass.inset(scheme), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? Color.brand(scheme) : Glass.hairline(scheme),
                              lineWidth: focused ? 2 : 1)
                .allowsHitTesting(false))
            .contentShape(Rectangle())
    }
}

struct SettingsForm: View {
    let onSave: () -> Void
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
        VStack(spacing: 0) {
            ScrollView {
                groups
                    .padding(.horizontal, UI.hPad)
                    .padding(.vertical, 6)
            }
            .scrollBounceBehavior(.basedOnSize)
            footerBar
        }
        .onAppear(perform: loadDrafts)
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("通用", icon: "slider.horizontal.3") {
                AppearanceRow(selection: model.config.appearanceMode) { mode in
                    model.update { $0.appearanceMode = mode }
                }
                Divider()
                row("自动刷新间隔") {
                    Menu {
                        Picker("自动刷新间隔", selection: $refreshDraft) {
                            ForEach([5, 15, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                        }
                    } label: {
                        HStack {
                            Text("\(refreshDraft) 分钟")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.footnote)
                        }
                        .modifier(SettingsFieldSurface())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                    .accessibilityLabel("自动刷新间隔，\(refreshDraft) 分钟")
                }
                hint("按此间隔更新所有已连接的数据源，也可以点击左栏顶部手动刷新。")
                row("备注名") {
                    TextField("OpenAI 仪表盘", text: $labelDraft)
                        .focused($focusedField, equals: .label)
                        .modifier(SettingsFieldSurface(focused: focusedField == .label))
                }
                hint("显示在左栏顶部，留空使用默认名称。")
            }
            section("API 用量", icon: "chevron.left.forwardslash.chevron.right") {
                row("Admin Key") {
                    HStack(spacing: 4) {
                        Group {
                            if showKey {
                                TextField("sk-admin-…", text: $keyDraft)
                            } else {
                                SecureField("sk-admin-…", text: $keyDraft)
                            }
                        }
                        .focused($focusedField, equals: .key)
                        .accessibilityLabel("Admin Key")
                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .frame(width: 28, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showKey ? "隐藏 Admin Key" : "显示 Admin Key")
                    }
                    .modifier(SettingsFieldSurface(focused: focusedField == .key))
                }
                hint("使用 sk-admin- 开头的组织管理员 Key。普通项目 Key 无法查询组织用量。Key 在本机加密保存。")
                if let keyFingerprint {
                    Text(keyFingerprint).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    Button(isTesting ? "测试中…" : "测试连接") { runTest() }
                        .disabled(isTesting || keyDraft.isEmpty)
                    Button("清除 Key") { clearKey() }.disabled(keyDraft.isEmpty)
                    Link(destination: adminKeysURL) {
                        HStack(spacing: 4) {
                            Text("管理 Admin Key")
                            Image(systemName: "arrow.up.right").accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(TextTone.secondary(scheme))
                    .help("在浏览器中打开 OpenAI 平台的 Admin Keys 页面")
                }
                if let testMessage {
                    Text(testMessage).font(.system(size: 11))
                        .foregroundStyle(testOK ? Color.brand(scheme) : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                row("项目 ID") {
                    TextField("选填 · proj_…", text: $projectDraft)
                        .focused($focusedField, equals: .project)
                        .modifier(SettingsFieldSurface(focused: focusedField == .project))
                }
                hint("留空统计整个组织，填写后仅统计该项目。花费与用量按 UTC 自然日统计。")
                Divider()
                HStack {
                    Text("显示实时余额")
                    Spacer()
                    Toggle("显示实时余额", isOn: $creditDraft)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)

                }
                hint("余额通过本机的 OpenAI 平台登录会话读取，Admin Key 无法读取余额。登录态由本机 WebKit 管理，App 不保存密码或明文 Cookie。关闭开关并保存后会清除平台登录态，下次需要重新登录。")
                HStack {
                    Text("OpenAI 平台")
                    Spacer()
                    Text(creditStatusText).foregroundStyle(TextTone.secondary(scheme))
                }
                HStack(spacing: 10) {
                    Button(model.liveCredit == nil ? "登录平台" : "重新登录") {
                        creditDraft = true
                        model.loginForCredit()
                    }
                    Button("退出登录") { model.clearCreditLogin() }
                }
            }
            section("ChatGPT 订阅", icon: "person") {
                HStack {
                    Text("ChatGPT 登录")
                    Spacer()
                    Text(subscriptionStatus).foregroundStyle(TextTone.secondary(scheme))
                }
                hint("订阅数据来自本软件内登录的 ChatGPT 网页会话；登录态由本机 WebKit 单独管理，不依赖本机 Codex，也不复用 API 余额的平台登录。")
                HStack(spacing: 10) {
                    Button(model.subscriptionLoginInProgress ? "返回登录窗口" : "登录 ChatGPT") {
                        model.loginForSubscription()
                    }
                    if model.config.hasConnectedSubscription {
                        Button("退出登录") { model.logoutSubscription() }
                    }
                }
            }
        }
        .font(.system(size: 13))
        .buttonStyle(GlassPillStyle(compact: true))
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(TextTone.secondary(scheme))
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(1)
    }

    private var subscriptionStatus: String {
        if model.subscriptionLoginInProgress { return "登录中…" }
        if !model.config.hasConnectedSubscription { return "未连接" }
        if model.subscriptionLoading { return "读取中…" }
        if model.subscriptionError != nil { return "读取失败" }
        if model.subscription != nil { return "已连接" }
        return "等待读取"
    }

    private func row<Content: View>(_ title: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 105, alignment: .leading)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var footerBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Text(appVersion).font(.caption).foregroundStyle(TextTone.secondary(scheme))
            Button("保存") { saveAndClose() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, UI.hPad)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func section<Content: View>(_ title: String,
                                        icon: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .padding(.bottom, 3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .glassCard(radius: 24)
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

    /// 保存后返回 API 用量页
    private func saveAndClose() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if key != model.config.adminKey {
            let saved = key.isEmpty ? ConfigStore.user.credentials.delete() : ConfigStore.user.credentials.save(key)
            guard saved else {
                testOK = false
                testMessage = "无法更新本地加密凭据，本次设置未保存。"
                return
            }
        }
        model.update { cfg in
            cfg.adminKey = key
            if !key.isEmpty { cfg.credentialReadFailed = false }
            cfg.projectID = projectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            cfg.accountLabel = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            cfg.refreshMinutes = refreshDraft
            cfg.showCredit = creditDraft
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
        onSave()
    }

    private func clearKey() {
        testOK = false
        guard model.clearKey() else {
            testMessage = "无法删除本地加密凭据，原凭据已保留。"
            return
        }
        keyDraft = ""
        testMessage = "已清除本地保存的 Admin Key"
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
