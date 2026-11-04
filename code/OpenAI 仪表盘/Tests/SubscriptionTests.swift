import Foundation

@main
struct SubscriptionTests {
    static func main() {
        var snapshot = SubscriptionSnapshot()
        let quota = """
        {"email":"linda@example.com","plan_type":"prolite",
         "rate_limit":{"primary_window":{"used_percent":68,"limit_window_seconds":604800,"reset_at":1793860388}},
         "rate_limit_reset_credits":{"available_count":3}}
        """
        precondition(snapshot.applyWebResponse(path: "/backend-api/wham/usage", body: quota))
        precondition(snapshot.remainingPercent == 32)
        precondition(snapshot.resetCredits == 3)
        precondition(snapshot.displayPlan == "Pro")
        precondition(snapshot.maskedEmail == "li***@example.com")
        precondition(snapshot.weeklyReset == Date(timeIntervalSince1970: 1793860388))

        let credits = """
        {"available_count":2,"credits":[
          {"id":"later","status":"available","expires_at":"2026-12-02T06:25:00Z"},
          {"id":"used","status":"claimed","expires_at":"2026-11-01T00:00:00Z"},
          {"id":"earlier","status":"available","expires_at":"2026-11-07T07:21:00.000Z"}]}
        """
        precondition(snapshot.applyWebResponse(path: "/backend-api/wham/rate-limit-reset-credits", body: credits))
        precondition(snapshot.resetCredits == 2)
        precondition(snapshot.resetCreditDetails.map(\.id) == ["earlier", "later"])

        let counts = """
        {"data":[{"date":"2026-11-03",
          "totals":{"text_total_tokens":151047841,"turns":129},
          "models":[{"model":"gpt-6-astra","turns":90},{"model":"gpt-6-sol","turns":39}],
          "clients":[{"client_id":"CODEX_DESKTOP_APP","turns":129}]}]}
        """
        precondition(snapshot.applyWebResponse(path: "/backend-api/wham/analytics/daily-workspace-usage-counts",
                                               body: counts))
        precondition(snapshot.days["2026-11-03"]?.tokens == 151_047_841)
        precondition(snapshot.days["2026-11-03"]?.messages == 129)
        precondition(snapshot.days["2026-11-03"]?.messageModels["gpt-6-astra"] == 90)
        precondition(snapshot.hasTokens && snapshot.hasMessages)

        let usage = """
        {"data":[{"date":"2026-11-03","attribution":[
          {"thread_source":"automation","turn_trigger":"user_message","model":"gpt-6-astra",
           "surface":"desktop_app","value":1.5}]}]}
        """
        precondition(snapshot.applyWebResponse(path: "/backend-api/wham/usage/daily-token-usage-breakdown",
                                               body: usage))
        precondition(snapshot.days["2026-11-03"]?.usage.first?.surface == "desktop_app")
        precondition(snapshot.days["2026-11-03"]?.usage.first?.value == 1.5)

        let plugin = """
        {"data":[{"date":"2026-11-03","plugin_usage_overviews":[
          {"display_name":"Codex App Tools","invocation_counts":27}]}]}
        """
        let skill = """
        {"data":[{"date":"2026-11-03","plugin_usage_overviews":[
          {"display_name":"Computer Use","invocation_counts":14}]}]}
        """
        precondition(snapshot.applyWebResponse(path: "/backend-api/wham/analytics/daily-plugin-usage-metrics",
                                               body: plugin))
        precondition(snapshot.applyWebResponse(path: "/backend-api/wham/analytics/daily-skill-usage-metrics",
                                               body: skill))
        precondition(snapshot.days["2026-11-03"]?.tools.values.reduce(0, +) == 41)
        precondition(!snapshot.applyWebResponse(path: "/unrelated", body: counts))
        precondition(!snapshot.applyWebResponse(path: "/backend-api/wham/usage", body: "invalid"))
        print("Subscription web data OK")
    }
}
