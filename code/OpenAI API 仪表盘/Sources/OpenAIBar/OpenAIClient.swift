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
    var topItems: [ItemCost] = []
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
    func fetchUsageAndCost(days: Int = 30) async throws -> (daily: [DayPoint], topItems: [ItemCost]) {
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

        // 成本：按天累计 + 按服务项累计（只统计最近 7 天用于 Top 榜）
        let sevenDaysAgo = cal.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart

        var costByDay: [Date: Double] = [:]
        var itemsByDay: [String: (cost: Double, tokens: Int)] = [:]

        for bucket in costs.data {
            let day = Date(timeIntervalSince1970: TimeInterval(bucket.startTime))
            let dayCost = bucket.results.reduce(0.0) { $0 + $1.amount.value }
            costByDay[day, default: 0] += dayCost
            guard day >= sevenDaysAgo else { continue }
            for r in bucket.results {
                let name = (r.lineItem?.isEmpty == false ? r.lineItem! : "其他")
                var entry = itemsByDay[name] ?? (0, 0)
                entry.cost += r.amount.value
                itemsByDay[name] = entry
            }
        }

        // 用量：按天累计 token / 请求数
        var tokensByDay: [Date: Int] = [:]
        var requestsByDay: [Date: Int] = [:]
        var tokensByModel: [String: Int] = [:]

        for bucket in usage.data {
            let day = Date(timeIntervalSince1970: TimeInterval(bucket.startTime))
            for r in bucket.results {
                let t = (r.inputTokens ?? 0) + (r.outputTokens ?? 0)
                tokensByDay[day, default: 0] += t
                requestsByDay[day, default: 0] += (r.numModelRequests ?? 0)
                if day >= sevenDaysAgo, let model = r.model, !model.isEmpty {
                    tokensByModel[model, default: 0] += t
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

        // Top 花费项：合并 token 数，按金额降序
        var topItems = itemsByDay.map { name, value -> ItemCost in
            ItemCost(id: name, name: name, cost: value.cost, tokens: 0)
        }
        for i in topItems.indices {
            topItems[i] = ItemCost(id: topItems[i].id,
                                   name: topItems[i].name,
                                   cost: topItems[i].cost,
                                   tokens: tokensByModel[topItems[i].name] ?? 0)
        }
        topItems.sort { $0.cost > $1.cost }

        return (daily, Array(topItems.prefix(5)))
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
            let numModelRequests: Int?
            let model: String?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
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
