import Foundation

enum TokenUnit: Int {
    case thousand = 1_000
    case million = 1_000_000
    case billion = 1_000_000_000

    init(for value: Int) {
        if value >= Self.billion.rawValue {
            self = .billion
        } else if value >= Self.million.rawValue {
            self = .million
        } else {
            self = .thousand
        }
    }

    private var suffix: String {
        switch self {
        case .thousand: return "K"
        case .million: return "M"
        case .billion: return "B"
        }
    }

    func format(_ value: Int) -> String {
        let scaled = Double(value) / Double(rawValue)
        if self != .thousand, value > 0, scaled < 0.01 {
            return "<0.01" + suffix
        }
        let digits = self == .thousand && scaled < 1 ? 3 : 2
        let number = scaled.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
            .grouping(.never).precision(.fractionLength(0...digits)))
        return number + suffix
    }
}
