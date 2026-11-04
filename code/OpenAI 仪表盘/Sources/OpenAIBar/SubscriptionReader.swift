import Foundation

struct ResetCredit: Identifiable {
    let id: String
    let expiresAt: Date?
}

struct UsageAttribution {
    let feature: String
    let model: String
    let surface: String
    let trigger: String
    let value: Double
}

struct SubscriptionDay: Identifiable {
    let id: String
    var tokens: Int?
    var messages: Int?
    var messageModels: [String: Int] = [:]
    var messageClients: [String: Int] = [:]
    var usage: [UsageAttribution] = []
    var plugins: [String: Int] = [:]
    var skills: [String: Int] = [:]
    var tools: [String: Int] { plugins.merging(skills, uniquingKeysWith: +) }
}

struct SubscriptionSnapshot {
    var email: String?
    var plan: String?
    var remainingPercent: Int?
    var weeklyReset: Date?
    var resetCredits: Int?
    var resetCreditDetails: [ResetCredit] = []
    var days: [String: SubscriptionDay] = [:]
    var hasQuota = false
    var hasTokens = false
    var hasUsageHistory = false
    var hasTools = false
    var hasMessages = false
    var fetchedAt = Date()

    var sortedDays: [SubscriptionDay] { days.values.sorted { $0.id < $1.id } }

    var maskedEmail: String? {
        guard let email else { return nil }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        let prefix = parts[0].prefix(min(2, parts[0].count - 1))
        return "\(prefix)***@\(parts[1])"
    }

    var displayPlan: String? {
        switch plan?.lowercased() {
        case "free": return "Free"
        case "plus": return "Plus"
        case "pro", "prolite": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        default: return nil
        }
    }

    @discardableResult
    mutating func applyWebResponse(path: String, body: String) -> Bool {
        guard let bytes = body.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else { return false }
        if path == "/backend-api/wham/usage" {
            email = root["email"] as? String
            plan = root["plan_type"] as? String
            let limit = root["rate_limit"] as? [String: Any]
            let windows = ["primary_window", "secondary_window"].compactMap { limit?[$0] as? [String: Any] }
            let week = windows.first { ($0["limit_window_seconds"] as? NSNumber)?.intValue == 604_800 }
            if let used = (week?["used_percent"] as? NSNumber)?.intValue, (0...100).contains(used) {
                remainingPercent = 100 - used
            }
            if let reset = (week?["reset_at"] as? NSNumber)?.doubleValue, reset > 0 {
                weeklyReset = Date(timeIntervalSince1970: reset)
            }
            let credits = root["rate_limit_reset_credits"] as? [String: Any]
            resetCredits = (credits?["available_count"] as? NSNumber)?.intValue
            hasQuota = true
        } else if path == "/backend-api/wham/rate-limit-reset-credits" {
            resetCredits = (root["available_count"] as? NSNumber)?.intValue ?? resetCredits
            let credits = root["credits"] as? [[String: Any]] ?? []
            resetCreditDetails = credits.compactMap { item in
                guard item["status"] as? String == "available", let id = item["id"] as? String else { return nil }
                let expiry = (item["expires_at"] as? String).flatMap(Self.parseISODate)
                return ResetCredit(id: id, expiresAt: expiry)
            }.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        } else if path == "/backend-api/wham/analytics/daily-workspace-usage-counts" {
            for item in root["data"] as? [[String: Any]] ?? [] {
                guard let date = item["date"] as? String else { continue }
                var day = days[date] ?? SubscriptionDay(id: date)
                let totals = item["totals"] as? [String: Any] ?? [:]
                day.tokens = (totals["text_total_tokens"] as? NSNumber)?.intValue
                day.messages = (totals["turns"] as? NSNumber)?.intValue
                day.messageModels = Self.counts(item["models"], key: "model", value: "turns")
                day.messageClients = Self.counts(item["clients"], key: "client_id", value: "turns")
                days[date] = day
            }
            hasTokens = true
            hasMessages = true
        } else if path == "/backend-api/wham/usage/daily-token-usage-breakdown" {
            for item in root["data"] as? [[String: Any]] ?? [] {
                guard let date = item["date"] as? String else { continue }
                var day = days[date] ?? SubscriptionDay(id: date)
                day.usage = (item["attribution"] as? [[String: Any]] ?? []).compactMap { row in
                    guard let value = (row["value"] as? NSNumber)?.doubleValue else { return nil }
                    return UsageAttribution(feature: row["thread_source"] as? String ?? "其他",
                                            model: row["model"] as? String ?? "其他",
                                            surface: row["surface"] as? String ?? "其他",
                                            trigger: row["turn_trigger"] as? String ?? "其他",
                                            value: value)
                }
                days[date] = day
            }
            hasUsageHistory = true
        } else if path == "/backend-api/wham/analytics/daily-plugin-usage-metrics"
                    || path == "/backend-api/wham/analytics/daily-skill-usage-metrics" {
            for item in root["data"] as? [[String: Any]] ?? [] {
                guard let date = item["date"] as? String else { continue }
                var day = days[date] ?? SubscriptionDay(id: date)
                let values = Self.counts(item["plugin_usage_overviews"], key: "display_name", value: "invocation_counts")
                if path.contains("daily-plugin") { day.plugins = values } else { day.skills = values }
                days[date] = day
            }
            hasTools = true
        } else {
            return false
        }
        fetchedAt = .now
        return true
    }

    private static func counts(_ raw: Any?, key: String, value: String) -> [String: Int] {
        var result: [String: Int] = [:]
        for row in raw as? [[String: Any]] ?? [] {
            guard let name = row[key] as? String, let count = (row[value] as? NSNumber)?.intValue else { continue }
            result[name, default: 0] += count
        }
        return result
    }

    private static func parseISODate(_ value: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
