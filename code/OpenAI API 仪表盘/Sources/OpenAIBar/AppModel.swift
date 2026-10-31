import Foundation
import SwiftUI

/// 失败类型，决定界面给用户哪一个动作
enum ErrorKind {
    case noKey      // 还没填 Key → 去填
    case auth       // Key 无效 / 权限不足 → 重新填
    case other      // 网络等 → 重试
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

    private var timer: Timer?

    init() {
        self.config = ConfigStore.load()
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
        snap.topItems = [
            ItemCost(id: "gpt-4o", name: "gpt-4o", cost: 8.42, tokens: 1_240_000),
            ItemCost(id: "o3", name: "o3", cost: 4.18, tokens: 310_000),
            ItemCost(id: "gpt-4o-mini", name: "gpt-4o-mini", cost: 1.96, tokens: 2_880_000),
            ItemCost(id: "text-embedding-3-large", name: "text-embedding-3-large", cost: 0.72, tokens: 940_000),
            ItemCost(id: "gpt-image-1", name: "gpt-image-1", cost: 0.31, tokens: 0)
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
        if keyChanged || projectChanged {
            snapshot = nil
            hasLoadedOnce = false
            Task { await refresh() }
        }
    }

    /// 彻底清除已保存的 Key
    func clearKey() {
        KeyStore.delete()
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
            let (daily, topItems) = try await core
            let (balance, note) = await balancePair

            var snap = Snapshot()
            snap.daily = daily
            snap.topItems = topItems

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
