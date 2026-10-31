import Foundation
import SwiftUI

/// 失败类型，决定界面给用户哪一个动作
enum ErrorKind {
    case noKey      // 还没填 Key → 去填
    case auth       // Key 无效 / 权限不足 → 重新填
    case other      // 网络等 → 重试
}

/// 实时余额（来自平台登录态）
struct LiveCredit {
    var available: Double
    var granted: Double?
    var used: Double?
    var at: Date
}

@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig {
        didSet { persistIfNeeded(old: oldValue) }
    }
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published private(set) var errorHint: String?
    @Published private(set) var errorKind: ErrorKind?
    @Published private(set) var hasLoadedOnce = false

    /// 实时余额（需用户开启；官方 API 拿不到，只能走平台登录态）
    let creditBridge = CreditBridge()
    @Published private(set) var liveCredit: LiveCredit?
    /// 最近一次成功读到的余额。只用于「登录已失效 / 刷新失败」时说明「上次读到多少」，不当作现值
    @Published private(set) var lastKnownCredit: LiveCredit?
    @Published private(set) var creditState: CreditBridge.State = .off

    private var timer: Timer?

    init() {
        self.config = ConfigStore.load()
        creditBridge.onChange = { [weak self] in self?.syncCredit() }
        if config.showCredit { creditBridge.start() }
        startAutoRefresh()
        Task { await refresh() }
    }

    /// 预览用：注入假数据，不发网络请求
    init(demo: Bool) {
        self.config = AppConfig()
        if demo { loadDemo() }
    }

    func loadDemo() {
        var snap = Snapshot()
        let cal = OpenAIClient.utcCalendar
        let today = cal.startOfDay(for: .now)
        let shape: [Double] = [0.42, 1.28, 0.66, 2.10, 1.85, 0.94, 3.42, 1.12,
                               0.58, 1.96, 2.44, 0.72, 1.30, 2.05, 0.88, 4.12,
                               1.64, 0.52, 2.77, 1.09, 3.05, 0.68, 1.42, 2.31,
                               0.96, 1.78, 4.66, 2.19, 1.24, 0.91]
        var daily: [DayPoint] = []
        for (i, cost) in shape.enumerated() {
            guard let day = cal.date(byAdding: .day, value: -(shape.count - 1 - i), to: today) else { continue }
            daily.append(DayPoint(id: day,
                                  cost: cost,
                                  tokens: Int(cost * 268_000),
                                  requests: Int(cost * 12)))
        }
        snap.daily = daily
        snap.todayCost = daily.last?.cost ?? 0
        snap.todayTokens = daily.last?.tokens ?? 0
        snap.todayRequests = daily.last?.requests ?? 0
        let last7 = daily.suffix(7)
        snap.cost7 = last7.reduce(0) { $0 + $1.cost }
        snap.tokens7 = last7.reduce(0) { $0 + $1.tokens }
        snap.requests7 = last7.reduce(0) { $0 + $1.requests }
        snap.cost30 = daily.reduce(0) { $0 + $1.cost }
        snap.tokens30 = daily.reduce(0) { $0 + $1.tokens }
        snap.costBreakdown.today = [
            ItemCost(id: "gpt-4o", name: "gpt-4o", cost: 1.85, tokens: 210_000, requests: 140),
            ItemCost(id: "gpt-4o-mini", name: "gpt-4o-mini", cost: 0.42, tokens: 610_000, requests: 900),
            ItemCost(id: "o3", name: "o3", cost: 0.28, tokens: 22_000, requests: 15),
            ItemCost(id: "gpt-image-1", name: "gpt-image-1", cost: 0.12, tokens: 0, requests: 6)
        ]
        snap.costBreakdown.last7 = [
            ItemCost(id: "gpt-4o", name: "gpt-4o", cost: 8.42, tokens: 1_240_000, requests: 830),
            ItemCost(id: "o3", name: "o3", cost: 4.18, tokens: 310_000, requests: 210),
            ItemCost(id: "gpt-4o-mini", name: "gpt-4o-mini", cost: 1.96, tokens: 2_880_000, requests: 4_100),
            ItemCost(id: "text-embedding-3-large", name: "text-embedding-3-large", cost: 0.72, tokens: 940_000, requests: 1_200),
            ItemCost(id: "gpt-image-1", name: "gpt-image-1", cost: 0.31, tokens: 0, requests: 12)
        ]
        snap.costBreakdown.last30 = [
            ItemCost(id: "gpt-4o", name: "gpt-4o", cost: 21.40, tokens: 5_120_000, requests: 3_400),
            ItemCost(id: "o3", name: "o3", cost: 9.66, tokens: 780_000, requests: 520),
            ItemCost(id: "gpt-4o-mini", name: "gpt-4o-mini", cost: 4.18, tokens: 6_900_000, requests: 9_800),
            ItemCost(id: "text-embedding-3-large", name: "text-embedding-3-large", cost: 2.05, tokens: 2_600_000, requests: 3_300),
            ItemCost(id: "gpt-image-1", name: "gpt-image-1", cost: 0.94, tokens: 0, requests: 38)
        ]
        snap.balance = BalanceInfo(limit: 50, used: 15.62, available: 34.38,
                                   source: "API 计费额度上限 − 本月已用（估算）", isExact: false)
        snap.fetchedAt = .now
        snapshot = snap
        hasLoadedOnce = true
    }

    /// 预览用：渲染「未配置 Key」的状态
    func loadDemoEmpty() {
        snapshot = nil
        errorText = "还没有配置 Admin Key"
        errorHint = "Admin Key 只能在设置里填入，App 不会内置任何 Key。"
        errorKind = .noKey
    }

    // MARK: 配置

    private var suppressPersist = false

    private func persistIfNeeded(old: AppConfig) {
        guard !suppressPersist else { return }
        let keyChanged = old.adminKey != config.adminKey
        let projectChanged = old.projectID != config.projectID

        if keyChanged {
            let trimmed = config.trimmedKey
            if trimmed.isEmpty {
                KeyStore.delete()
            } else if !KeyStore.save(trimmed) {
                errorText = "无法写入 macOS 钥匙串"
                errorHint = "Key 未能保存。请检查钥匙串访问权限后重试。"
            }
        }

        ConfigStore.save(config)
        if old.refreshMinutes != config.refreshMinutes { startAutoRefresh() }
        if old.showCredit != config.showCredit {
            if config.showCredit {
                creditBridge.start()
                creditBridge.refresh(stale: 0)
            } else {
                // 关闭开关 = 退出登录：停掉读取，并清空 App 自己的 WebKit 容器。
                // 开关默认关闭是隐私姿态的一部分，留着 cookie 等于「关了但没关」。
                creditBridge.stop()
                creditBridge.clearSession { [weak self] in self?.syncCredit() }
                liveCredit = nil
                lastKnownCredit = nil
                // 忘掉「曾经连过」：再开启时回到「从未登录」，而不是「登录已失效」。
                // 这里要绕过 suppressPersist 直接落盘（外层已保存过一次 config）。
                if config.hasConnectedCredit {
                    suppressPersist = true
                    config.hasConnectedCredit = false
                    suppressPersist = false
                    ConfigStore.save(config)
                }
                syncCredit()
            }
        }
        if keyChanged || projectChanged {
            snapshot = nil
            hasLoadedOnce = false
            Task { await refresh() }
        }
    }

    /// 彻底清除已保存的 Key
    func clearKey() {        KeyStore.delete()
        suppressPersist = true
        config.adminKey = ""
        suppressPersist = false
        ConfigStore.save(config)
        snapshot = nil
        hasLoadedOnce = false
        errorText = "还没有配置 Admin Key"
        errorHint = "在「设置」里填入 Admin Key，它会被保存到 macOS 钥匙串。"
        errorKind = .noKey
    }

    func update(_ mutate: (inout AppConfig) -> Void) {
        var copy = config
        mutate(&copy)
        config = copy
    }

    // MARK: 实时余额

    private func syncCredit() {
        creditState = creditBridge.state

        // 上次读数：只作文案，任何时候都不参与「当前余额」的判断
        if let k = creditBridge.lastKnown {
            lastKnownCredit = LiveCredit(available: k.available, granted: k.granted, used: k.used, at: k.at)
        } else {
            lastKnownCredit = nil
        }

        // 需要重新登录时必须丢掉现值：否则面板会一直显示上一次读到的数字，
        // 把「登录已失效 / 需要登录」卡片永久盖住。
        if creditBridge.state == .needsLogin {
            liveCredit = nil
            return
        }
        if let a = creditBridge.available {
            liveCredit = LiveCredit(available: a,
                                    granted: creditBridge.granted,
                                    used: creditBridge.used,
                                    at: creditBridge.updatedAt ?? .now)
            // 记住「读到过」，用来把「登录已失效」和「从未登录」分开显示
            if !config.hasConnectedCredit { config.hasConnectedCredit = true }
        } else {
            liveCredit = nil
        }
    }

    /// 打开登录窗口；登录成功后立刻重读余额。
    /// 开关没打开时一并打开（写配置会触发 start + 立即加载），让「登录」成为一步操作。
    func loginForCredit() {
        if !config.showCredit {
            config.showCredit = true
        } else if creditBridge.state == .off {
            creditBridge.start()
        }
        CreditLoginWindow.show { [weak self] in
            // 登录窗口刚关，cookie 可能还没完全同步到隐藏 WebView，稍等再重查，
            // 否则 forceReload 可能又带着旧（无）登录态被判成「需要登录」。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.creditBridge.forceReload()
            }
        }
    }

    func retryCredit() {
        creditBridge.forceReload()
    }

    /// 面板打开时：先把卡死的 loading 救回来，再按 15 分钟节流决定是否重读
    func refreshCreditOnPanelOpen() {
        guard config.showCredit else { return }
        creditBridge.recoverIfStuck()
        creditBridge.refresh(stale: 900)
    }

    /// 清除平台登录态（只清 App 自己的 WebKit 存储，不影响浏览器）
    func clearCreditLogin() {
        // 连同「读到过」的标记一起清掉：之后应当回到「从未登录」的界面
        if config.hasConnectedCredit { config.hasConnectedCredit = false }
        creditBridge.clearSession { [weak self] in
            self?.syncCredit()
        }
    }

    /// 预览用：伪造一条实时余额
    func loadDemoCredit() {
        demoCreditFlags(hasConnected: true)
        liveCredit = LiveCredit(available: 12.51, granted: 16.0, used: 3.49, at: .now)
        lastKnownCredit = liveCredit
        creditState = .ready
    }

    /// 预览用：余额需要登录的状态（从未登录过）
    func loadDemoCreditLogin() {
        demoCreditFlags(hasConnected: false)
        liveCredit = nil
        lastKnownCredit = nil
        creditState = .needsLogin
    }

    /// 预览用：登录已失效（以前读到过，现在会话过期）
    func loadDemoCreditExpired() {
        demoCreditFlags(hasConnected: true)
        liveCredit = nil
        lastKnownCredit = LiveCredit(available: 12.51, granted: 16.0, used: 3.49,
                                     at: Date().addingTimeInterval(-3 * 3600))
        creditState = .needsLogin
    }

    /// 预览不能写用户的真实配置（demo 只是画界面）
    private func demoCreditFlags(hasConnected: Bool) {
        suppressPersist = true
        config.showCredit = true
        config.hasConnectedCredit = hasConnected
        suppressPersist = false
    }

    // MARK: 定时刷新

    func startAutoRefresh() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, config.refreshMinutes) * 60)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshIfIdle()
            }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func refreshIfIdle() async {
        guard !isLoading else { return }
        await refresh()
    }

    // MARK: 数据加载

    func refresh() async {
        // 余额与 Key 无关：只要开启了实时余额，就顺带刷一次（15 分钟内不重复整页加载）
        if config.showCredit { creditBridge.refresh(stale: 900) }

        guard config.hasKey else {
            errorText = "还没有配置 Admin Key"
            errorHint = "Admin Key 只能在设置里填入，App 不会内置任何 Key。"
            errorKind = .noKey
            return
        }
        guard !isLoading else { return }

        isLoading = true
        errorText = nil
        errorHint = nil
        errorKind = nil

        let client = OpenAIClient(adminKey: config.trimmedKey,
                                  projectID: config.projectID.trimmingCharacters(in: .whitespaces))

        do {
            async let core = client.fetchUsageAndCost(days: 30)
            async let balancePair = client.fetchBalance()
            let (daily, breakdown) = try await core
            let (balance, note) = await balancePair

            var snap = Snapshot()
            snap.daily = daily
            snap.costBreakdown = breakdown

            let today = daily.last
            snap.todayCost = today?.cost ?? 0
            snap.todayTokens = today?.tokens ?? 0
            snap.todayRequests = today?.requests ?? 0

            let last7 = daily.suffix(7)
            snap.cost7 = last7.reduce(0) { $0 + $1.cost }
            snap.tokens7 = last7.reduce(0) { $0 + $1.tokens }
            snap.requests7 = last7.reduce(0) { $0 + $1.requests }

            snap.cost30 = daily.reduce(0) { $0 + $1.cost }
            snap.tokens30 = daily.reduce(0) { $0 + $1.tokens }
            snap.balance = balance
            snap.balanceNote = note
            snap.fetchedAt = .now

            snapshot = snap
            hasLoadedOnce = true
        } catch let err as APIError {
            errorText = err.message
            errorHint = err.hint
            errorKind = (err.status == 401 || err.status == 403) ? .auth : .other
        } catch {
            if let urlErr = error as? URLError {
                // 国内访问 api.openai.com 基本都要走代理，这里给最可能的排查方向
                switch urlErr.code {
                case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
                     .networkConnectionLost, .timedOut, .dnsLookupFailed:
                    errorText = "连不上 api.openai.com"
                    errorHint = "多是代理没开：确认 Clash / VPN 已运行，然后在 App 里点「重试」。"
                default:
                    errorText = urlErr.localizedDescription
                    errorHint = "请检查网络或代理设置。"
                }
            } else {
                errorText = error.localizedDescription
                errorHint = "请检查网络或代理设置。"
            }
            errorKind = .other
        }

        isLoading = false
    }

    /// 设置页里点「测试连接」
    func testConnection(_ key: String) async -> (Bool, String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "请先填入 Key") }
        do {
            try await OpenAIClient.verify(adminKey: trimmed)
            return (true, "连接成功，该 Key 可以读取组织用量数据。")
        } catch let err as APIError {
            let hint = err.hint.map { " " + $0 } ?? ""
            return (false, err.message + hint)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - 格式化

enum Fmt {
    static func money(_ value: Double) -> String {
        let v = abs(value)
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.currencySymbol = "$"
        if v == 0 {
            f.minimumFractionDigits = 0
            f.maximumFractionDigits = 0
        } else if v < 0.01 {
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 4
        } else if v < 1 {
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 3
        } else {
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
        }
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func tokens(_ value: Int) -> String {
        let v = Double(value)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
        return "\(value)"
    }

    static func updatedLabel(_ date: Date) -> String {
        let s = max(0, Date().timeIntervalSince(date))
        if s < 15 { return "刚刚更新" }
        if s < 60 { return "\(Int(s)) 秒前更新" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前更新" }
        if s < 86400 { return "\(Int(s / 3600)) 小时前更新" }
        return "\(Int(s / 86400)) 天前更新"
    }

    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
