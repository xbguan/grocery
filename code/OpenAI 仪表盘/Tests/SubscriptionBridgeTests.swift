import Foundation

@main
@MainActor
struct SubscriptionBridgeTests {
    static func main() {
        let overview = URL(string: "https://chatgpt.com/settings/usage")!
        let analytics = URL(string: "https://chatgpt.com/settings/usage?tab=analytics")!

        precondition(SubscriptionBridge.pageURL == overview)
        precondition(SubscriptionBridge.loginURL.absoluteString ==
                     "https://chatgpt.com/auth/login?next=%2Fsettings%2Fusage")
        precondition(SubscriptionBridge.analyticsPage(afterResponse: "/backend-api/wham/usage", at: overview) == analytics)
        precondition(SubscriptionBridge.analyticsPage(afterResponse: "/backend-api/wham/rate-limit-reset-credits", at: overview) == nil)
        precondition(SubscriptionBridge.analyticsPage(afterResponse: "/backend-api/wham/usage", at: analytics) == nil)
        var cached = SubscriptionSnapshot()
        cached.hasQuota = true
        precondition(!SubscriptionBridge.hasFreshQuota(afterResponse: "/backend-api/wham/rate-limit-reset-credits", snapshot: cached))
        precondition(SubscriptionBridge.hasFreshQuota(afterResponse: "/backend-api/wham/usage", snapshot: cached))
        print("Subscription page navigation OK")
    }
}
