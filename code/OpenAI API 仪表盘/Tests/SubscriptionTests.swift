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
        precondition(legacy.plan == "pro" && legacy.remainingPercent == 72)
        print("Subscription fields OK")
    }
}
