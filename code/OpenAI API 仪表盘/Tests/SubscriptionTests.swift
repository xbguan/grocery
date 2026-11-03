import Foundation

@main
struct SubscriptionTests {
    static func main() {
        let weekly: [String: Any] = ["windowDurationMins": 10080, "usedPercent": 28, "resetsAt": 1793995200.0]
        let short: [String: Any] = ["windowDurationMins": 300, "usedPercent": 100]
        var snapshot = SubscriptionSnapshot(plan: "plus")
        snapshot.apply(["rateLimitsByLimitId": ["codex": ["primary": short, "secondary": weekly]],
                        "rateLimits": ["limitId": "other", "primary": short],
                        "rateLimitResetCredits": ["availableCount": 0]])
        precondition(snapshot.remainingPercent == 72 && snapshot.weeklyReset == Date(timeIntervalSince1970: 1793995200))
        precondition(snapshot.resetCredits == 0 && snapshot.plan == "plus")

        var missing = SubscriptionSnapshot()
        missing.apply(["rateLimits": ["limitId": "other", "primary": weekly]])
        precondition(missing.remainingPercent == nil && missing.resetCredits == nil)

        var legacy = SubscriptionSnapshot()
        legacy.apply(["rateLimits": ["primary": weekly, "planType": "pro"]])
        precondition(legacy.plan == nil && legacy.remainingPercent == 72)
        precondition(SubscriptionSnapshot(plan: "pro").displayPlan == "Pro")
        precondition(SubscriptionSnapshot(plan: "prolite").displayPlan == "Pro")
        precondition(SubscriptionSnapshot(plan: "unknown").displayPlan == nil)

        var credits = SubscriptionSnapshot(plan: "pro")
        credits.apply(["rateLimitResetCredits": ["availableCount": 3,
                                                 "credits": [
                                                    ["id": "later", "title": "Rate-limit reset", "status": "available", "expiresAt": 1796178300],
                                                    ["id": "used", "title": "Rate-limit reset", "status": "claimed", "expiresAt": 1796178300],
                                                    ["id": "earlier", "title": "Rate-limit reset", "status": "available", "expiresAt": 1794028860]
                                                 ]]])
        precondition(credits.resetCredits == 3)
        precondition(credits.resetCreditDetails.map(\.id) == ["earlier", "later"])
        precondition(credits.resetCreditDetails[0].expiresAt == Date(timeIntervalSince1970: 1794028860))

        var countOnly = SubscriptionSnapshot()
        countOnly.apply(["rateLimitResetCredits": ["availableCount": 2, "credits": NSNull()]])
        precondition(countOnly.resetCredits == 2 && countOnly.resetCreditDetails.isEmpty)
        print("Subscription fields OK")
    }
}
