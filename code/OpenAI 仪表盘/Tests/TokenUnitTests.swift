import Foundation

@main
struct TokenUnitTests {
    static func main() {
        let totals: [(Int, String)] = [
            (0, "0K"), (1, "0.001K"), (999, "0.999K"), (1_000, "1K"),
            (999_000, "999K"), (1_000_000, "1M"), (1_000_000_000, "1B"),
            (4_480_000_000, "4.48B")
        ]
        for (value, expected) in totals {
            precondition(TokenUnit(for: value).format(value) == expected)
        }

        let chartUnit = TokenUnit(for: 513_064_060)
        precondition(chartUnit.format(513_064_060) == "513.06M")
        precondition(chartUnit.format(600_000_000) == "600M")
        precondition(chartUnit.format(250_000) == "0.25M")
        precondition(chartUnit.format(1) == "<0.01M")
        precondition(chartUnit.format(0) == "0M")
        print("Token unit formatting OK")
    }
}
