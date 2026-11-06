import Foundation

@main
struct SubscriptionCountdownTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 0)

        precondition(SubscriptionCountdown.make(until: now.addingTimeInterval(6 * 86_400 + 4 * 3_600 + 41 * 60), asOf: now)?.text == "6d4h")
        precondition(SubscriptionCountdown.make(until: now.addingTimeInterval(86_400), asOf: now)?.text == "1d")
        precondition(SubscriptionCountdown.make(until: now.addingTimeInterval(21 * 3_600 + 29 * 60), asOf: now)?.text == "21h29m")
        precondition(SubscriptionCountdown.make(until: now.addingTimeInterval(3_600), asOf: now)?.text == "1h")
        precondition(SubscriptionCountdown.make(until: now.addingTimeInterval(29 * 60), asOf: now)?.text == "29m")
        precondition(SubscriptionCountdown.make(until: now.addingTimeInterval(30), asOf: now)?.text == "1m")
        precondition(SubscriptionCountdown.make(until: now.addingTimeInterval(86_400), asOf: now)?.isUrgent == false)
        precondition(SubscriptionCountdown.make(until: now.addingTimeInterval(86_399), asOf: now)?.isUrgent == true)
        precondition(SubscriptionCountdown.make(until: now, asOf: now) == nil)
        precondition(SubscriptionCountdown.make(until: now.addingTimeInterval(-60), asOf: now) == nil)

        print("Subscription countdown OK")
    }
}
