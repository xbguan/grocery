import Foundation

// MARK: - 展示模型

struct DayPoint: Identifiable {
    let id: Date
    let cost: Double
    let tokens: Int
    let requests: Int
}

struct ItemCost: Identifiable {
    let id: String
    let name: String
    let cost: Double
    let tokens: Int
    let requests: Int
}

/// 单个模型的 token 细分（与 costs 接口的 line_item 类别一一对应）。
struct ModelTokenBreakdown {
    var output = 0
    var cachedInput = 0
    var cacheWrite = 0          // 30 分钟内缓存写入
    var cacheWrite12h = 0       // 12 小时缓存写入
    var uncachedInput = 0
}

/// 「花费来源」按时间范围的三组 Top 榜（今日 / 近 7 天 / 近 30 天）。
struct CostBreakdown {
    var today: [ItemCost] = []
    var last7: [ItemCost] = []
    var last30: [ItemCost] = []

    var isEmpty: Bool { today.isEmpty && last7.isEmpty && last30.isEmpty }
}

struct BalanceInfo {
    /// 总额度上限（美元），nil 表示未知
    var limit: Double?
    /// 本期已用（美元）
    var used: Double?
    /// 剩余（美元）
    var available: Double?
    /// 数据来源说明
    var source: String
    var isExact: Bool
}

struct Snapshot {
    var todayCost: Double = 0
    var cost7: Double = 0
    var cost30: Double = 0
    var todayTokens: Int = 0
    var tokens7: Int = 0
    var tokens30: Int = 0
    var todayRequests: Int = 0
    var requests7: Int = 0
    var daily: [DayPoint] = []
    var costBreakdown: CostBreakdown = CostBreakdown()
    var balance: BalanceInfo?
    var balanceNote: String?
    var fetchedAt: Date = .now

    var todayAvgCostPerDay: Double {
        guard !daily.isEmpty else { return 0 }
        return cost7 / 7.0
    }
}

// MARK: - 错误

struct APIError: LocalizedError {
    let message: String
    let status: Int?

    var errorDescription: String? { message }

    var hint: String? {
        switch status {
        case 401:
            return "OpenAI 未识别这个 Key（invalid_api_key）：它可能已被撤销、轮换，或复制时缺了字符。请到后台重新生成一份 Admin key。"
        case 403:
            return "该 Key 权限不足。组织用量接口需要 Admin Key（sk-admin- 开头），普通项目 Key 无法读取。"
        case 429:
            return "请求过于频繁，稍后再试。"
        default:
            return nil
        }
    }
}

// MARK: - 客户端

struct OpenAIClient {
    let adminKey: String
    let projectID: String?

    private static let baseURL = "https://api.openai.com"

    // MARK: 网络基础

    private func rawGET(_ path: String, query: [String: String]) async throws -> Data {
        var comps = URLComponents(string: Self.baseURL + path)
        comps?.queryItems = query
            .map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        guard let url = comps?.url else {
            throw APIError(message: "无法构造请求地址", status: nil)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        req.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "响应格式异常", status: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(message: Self.errorMessage(from: data, status: http.statusCode),
                           status: http.statusCode)
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) async throws -> T {
        let data = try await rawGET(path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(message: "解析 \(path) 返回数据失败：\(error.localizedDescription)", status: nil)
        }
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
                return msg
            }
            if let msg = obj["message"] as? String {
                return msg
            }
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return String(text.prefix(300))
        }
        return "HTTP \(status)"
    }

    // MARK: 用量 / 成本

    /// 拉取最近 30 天（UTC 日对齐）的成本与用量
    func fetchUsageAndCost(days: Int = 30) async throws -> (daily: [DayPoint], breakdown: CostBreakdown) {
        let cal = Self.utcCalendar
        let todayStart = cal.startOfDay(for: .now)
        let span = max(1, min(days, 30))
        guard let start = cal.date(byAdding: .day, value: -(span - 1), to: todayStart) else {
            throw APIError(message: "日期计算失败", status: nil)
        }
        let startTime = String(Int(start.timeIntervalSince1970))

        var costQuery: [String: String] = [
            "start_time": startTime,
            "bucket_width": "1d",
            "limit": String(span),
            "group_by": "line_item"
        ]
        var usageQuery: [String: String] = [
            "start_time": startTime,
            "bucket_width": "1d",
            "limit": String(span),
            "group_by": "model"
        ]
        if let pid = projectID, !pid.isEmpty {
            costQuery["project_ids"] = pid
            usageQuery["project_ids"] = pid
        }

        // 转成不可变值，避免并发捕获可变变量
        let finalCostQuery = costQuery
        let finalUsageQuery = usageQuery

        async let costsResp: CostResponse = get("/v1/organization/costs",
                                                query: finalCostQuery, as: CostResponse.self)
        async let usageResp: UsageResponse = get("/v1/organization/usage/completions",
                                                 query: finalUsageQuery, as: UsageResponse.self)
        let costs = try await costsResp
        let usage = try await usageResp

        // 成本：按天 × line_item 明细（costs 接口按 line_item 分组）
        var costByDay: [Date: Double] = [:]
        var costByDayAndItem: [Date: [String: Double]] = [:]

        for bucket in costs.data {
            let day = Date(timeIntervalSince1970: TimeInterval(bucket.startTime))
            for r in bucket.results {
                let name = (r.lineItem?.isEmpty == false ? r.lineItem! : "其他")
                costByDayAndItem[day, default: [:]][name, default: 0] += r.amount.value
                costByDay[day, default: 0] += r.amount.value
            }
        }

        // 用量：按天累计 token / 请求数；同时按「天 × 模型」记细分 token，
        // 供「花费来源」按时间范围聚合。usage 接口只支持按 model 分组（不支持 line_item），
        // 所以 token 先按模型存，聚合时再按 line_item 的「模型前缀 + 类别」反查。
        var tokensByDay: [Date: Int] = [:]
        var requestsByDay: [Date: Int] = [:]
        var tokenByDayAndModel: [Date: [String: ModelTokenBreakdown]] = [:]
        var requestsByDayAndModel: [Date: [String: Int]] = [:]

        for bucket in usage.data {
            let day = Date(timeIntervalSince1970: TimeInterval(bucket.startTime))
            for r in bucket.results {
                let t = (r.inputTokens ?? 0) + (r.outputTokens ?? 0)
                tokensByDay[day, default: 0] += t
                requestsByDay[day, default: 0] += (r.numModelRequests ?? 0)
                if let model = r.model, !model.isEmpty {
                    var b = tokenByDayAndModel[day, default: [:]][model] ?? ModelTokenBreakdown()
                    b.output += (r.outputTokens ?? 0)
                    b.cachedInput += (r.inputCachedTokens ?? 0)
                    b.cacheWrite += (r.inputCacheWriteTokens ?? 0)
                    b.cacheWrite12h += (r.inputCacheWrite12hTokens ?? 0)
                    b.uncachedInput += (r.inputUncachedTokens ?? 0)
                    tokenByDayAndModel[day, default: [:]][model] = b
                    requestsByDayAndModel[day, default: [:]][model, default: 0] += (r.numModelRequests ?? 0)
                }
            }
        }

        // 组装连续的 30 天序列（缺失日补 0）
        var daily: [DayPoint] = []
        for offset in 0..<span {
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            daily.append(DayPoint(id: day,
                                  cost: costByDay[day] ?? 0,
                                  tokens: tokensByDay[day] ?? 0,
                                  requests: requestsByDay[day] ?? 0))
        }

        // 给定日期范围，聚合出该范围内的 Top 花费项（按 line_item，金额降序取前 5）。
        func aggregate(_ days: [Date]) -> [ItemCost] {
            var cost: [String: Double] = [:]
            var modelTok: [String: ModelTokenBreakdown] = [:]
            var modelReq: [String: Int] = [:]
            for day in days {
                for (name, c) in costByDayAndItem[day] ?? [:] {
                    cost[name, default: 0] += c
                }
                for (model, b) in tokenByDayAndModel[day] ?? [:] {
                    var m = modelTok[model] ?? ModelTokenBreakdown()
                    m.output += b.output
                    m.cachedInput += b.cachedInput
                    m.cacheWrite += b.cacheWrite
                    m.cacheWrite12h += b.cacheWrite12h
                    m.uncachedInput += b.uncachedInput
                    modelTok[model] = m
                }
                for (model, r) in requestsByDayAndModel[day] ?? [:] {
                    modelReq[model, default: 0] += r
                }
            }
            let items = cost.map { name, c -> ItemCost in
                let (model, category) = Self.splitLineItem(name)
                let tokens = modelTok[model].map { Self.categoryTokens(category, breakdown: $0) } ?? 0
                return ItemCost(id: name, name: name, cost: c,
                                tokens: tokens, requests: modelReq[model] ?? 0)
            }
            return Array(items.sorted { $0.cost > $1.cost }.prefix(5))
        }

        let todayOnly = [todayStart]
        let last7Days = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: todayStart) }
        let allDays = (0..<span).compactMap { cal.date(byAdding: .day, value: -$0, to: todayStart) }

        var breakdown = CostBreakdown()
        breakdown.today = aggregate(todayOnly)
        breakdown.last7 = aggregate(last7Days)
        breakdown.last30 = aggregate(allDays)

        return (daily, breakdown)
    }

    /// 把 line_item 名（"模型, 类别"）拆成模型名 + 类别。
    private static func splitLineItem(_ lineItem: String) -> (model: String, category: String) {
        let parts = lineItem.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return (parts.first ?? "", parts.count >= 2 ? parts[1].lowercased() : "")
    }

    /// 某类别的 token 数（对应 ModelTokenBreakdown 的一个细分字段）。
    private static func categoryTokens(_ category: String, breakdown: ModelTokenBreakdown) -> Int {
        switch category {
        case "output": return breakdown.output
        case "cached input": return breakdown.cachedInput
        case "cache writes": return breakdown.cacheWrite
        case "cache writes - 12hr": return breakdown.cacheWrite12h
        case "input": return breakdown.uncachedInput
        default: return 0
        }
    }

    // MARK: 余额（best-effort）

    /// 官方没有公开余额接口。这里依次尝试：credit_grants → subscription + usage 推算。
    func fetchBalance() async -> (info: BalanceInfo?, note: String?) {
        // 1) 老接口：直接给剩余额度（仅浏览器会话 key 可用，通常失败）
        if let data = try? await rawGET("/v1/dashboard/billing/credit_grants", query: [:]),
           let grants = try? JSONDecoder().decode(CreditGrants.self, from: data) {
            return (BalanceInfo(limit: grants.totalGranted,
                                used: grants.totalUsed,
                                available: grants.totalAvailable,
                                source: "credit_grants 接口（精确）",
                                isExact: true), nil)
        }

        // 2) API 平台计费额度上限 - 本期已用（与 ChatGPT 订阅无关）
        guard let subData = try? await rawGET("/v1/dashboard/billing/subscription", query: [:]),
              let sub = try? JSONDecoder().decode(BillingSubscription.self, from: subData) else {
            return (nil, "该 Key 无权读取账单信息（Admin Key 与项目 Key 均无法访问 OpenAI 的余额接口，官方未开放此能力）。")
        }

        let limit = sub.hardLimitUSD ?? sub.systemHardLimitUSD
        var used: Double?

        let cal = Self.localCalendar
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = cal.timeZone
        let query = ["start_date": fmt.string(from: monthStart), "end_date": fmt.string(from: now)]
        if let usageData = try? await rawGET("/v1/dashboard/billing/usage", query: query),
           let usage = try? JSONDecoder().decode(BillingUsage.self, from: usageData) {
            used = usage.totalUsage / 100.0   // 接口返回单位是美分
        }

        var available: Double?
        if let limit, let used { available = max(0, limit - used) }

        return (BalanceInfo(limit: limit,
                            used: used,
                            available: available,
                            source: "API 计费额度上限 − 本月已用（估算）",
                            isExact: false), nil)
    }

    // MARK: 工具

    static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }

    static var localCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// 轻量连通性/权限检测
    static func verify(adminKey: String) async throws {
        let client = OpenAIClient(adminKey: adminKey, projectID: nil)
        _ = try await client.rawGET("/v1/organization/costs",
                                    query: ["start_time": String(Int(Date().timeIntervalSince1970) - 86400),
                                            "bucket_width": "1d",
                                            "limit": "1"])
    }
}

// MARK: - DTO

private struct CostResponse: Decodable {
    struct Bucket: Decodable {
        let startTime: Int
        let results: [Item]

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case results
        }

        struct Item: Decodable {
            let amount: Amount
            let lineItem: String?

            enum CodingKeys: String, CodingKey {
                case amount
                case lineItem = "line_item"
            }

            struct Amount: Decodable {
                let value: Double
                let currency: String?
            }
        }
    }

    let data: [Bucket]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }
}

private struct UsageResponse: Decodable {
    struct Bucket: Decodable {
        let startTime: Int
        let results: [Item]

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case results
        }

        struct Item: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let inputCachedTokens: Int?
            let inputCacheWriteTokens: Int?
            let inputCacheWrite12hTokens: Int?
            let inputUncachedTokens: Int?
            let numModelRequests: Int?
            let model: String?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case inputCachedTokens = "input_cached_tokens"
                case inputCacheWriteTokens = "input_cache_write_tokens"
                case inputCacheWrite12hTokens = "input_cache_write_12h_tokens"
                case inputUncachedTokens = "input_uncached_tokens"
                case numModelRequests = "num_model_requests"
                case model
            }
        }
    }

    let data: [Bucket]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }
}

private struct CreditGrants: Decodable {
    let totalGranted: Double
    let totalUsed: Double
    let totalAvailable: Double

    enum CodingKeys: String, CodingKey {
        case totalGranted = "total_granted"
        case totalUsed = "total_used"
        case totalAvailable = "total_available"
    }
}

private struct BillingSubscription: Decodable {
    let hardLimitUSD: Double?
    let systemHardLimitUSD: Double?
    let softLimitUSD: Double?
    let planTitle: String?

    enum CodingKeys: String, CodingKey {
        case hardLimitUSD = "hard_limit_usd"
        case systemHardLimitUSD = "system_hard_limit_usd"
        case softLimitUSD = "soft_limit_usd"
        case planTitle = "plan_title"
    }
}

private struct BillingUsage: Decodable {
    let totalUsage: Double

    enum CodingKeys: String, CodingKey {
        case totalUsage = "total_usage"
    }
}
