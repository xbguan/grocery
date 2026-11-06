import Foundation

struct SubscriptionCountdown {
    let text: String
    let isUrgent: Bool

    static func make(until date: Date, asOf now: Date) -> Self? {
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else { return nil }

        if remaining >= 86_400 {
            let seconds = Int(remaining)
            let days = seconds / 86_400
            let hours = (seconds % 86_400) / 3_600
            return Self(text: hours == 0 ? "\(days)d" : "\(days)d\(hours)h", isUrgent: false)
        }

        let minutes = max(1, Int(remaining / 60))
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        let hoursText = hours == 0 ? "" : "\(hours)h"
        let minutesText = remainingMinutes == 0 ? "" : "\(remainingMinutes)m"
        return Self(text: hoursText + minutesText, isUrgent: true)
    }
}
