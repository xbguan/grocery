import Foundation

@main
enum CreditExpiryTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let multiple = """
        {
          "total_granted": 30, "total_used": 15, "total_available": 15,
          "grants": {"data": [
            {"grant_amount": 10, "used_amount": 10, "expires_at": 1500},
            {"grant_amount": 12, "used_amount": 2, "expires_at": 3000},
            {"grant_amount": 8, "used_amount": 3, "expires_at": 2000}
          ]}
        }
        """
        let summary = try JSONDecoder().decode(CreditSummary.self, from: Data(multiple.utf8))
        guard let expiry = summary.nextExpiration(asOf: now),
              expiry.date == Date(timeIntervalSince1970: 2000),
              expiry.remaining == 5 else {
            fatalError("Must select nearest unspent grant")
        }
        let countdown = CreditExpiry(date: now.addingTimeInterval(26.5 * 3600), remaining: 5)
        guard countdown.countdown(asOf: now) == "1d 2h",
              CreditExpiry(date: now.addingTimeInterval(1800), remaining: 5).countdown(asOf: now) == "<1h",
              CreditExpiry(date: now, remaining: 5).countdown(asOf: now) == "已到期" else {
            fatalError("Countdown must show remaining days and hours")
        }

        let expired = """
        {
          "total_available": 7,
          "grants": {"data": [
            {"grant_amount": 7, "used_amount": 0, "expires_at": 900}
          ]}
        }
        """
        let oldSummary = try JSONDecoder().decode(CreditSummary.self, from: Data(expired.utf8))
        guard oldSummary.nextExpiration(asOf: now) == nil else {
            fatalError("Must not display an expired grant")
        }

        let changedShape = """
        {"total_available": 7, "grants": {"items": []}}
        """
        let fallback = try JSONDecoder().decode(CreditSummary.self, from: Data(changedShape.utf8))
        guard fallback.totalAvailable == 7, fallback.nextExpiration(asOf: now) == nil else {
            fatalError("Unknown grant shape must not hide the balance")
        }

        let detailPage = """
        {"data": [{"grant_amount": 9, "used_amount": 1, "expires_at": 2500}]}
        """
        let details = try JSONDecoder().decode(CreditSummary.self, from: Data(detailPage.utf8))
        guard details.nextExpiration(asOf: now)?.remaining == 8 else {
            fatalError("Grant detail response must provide expiry without a balance total")
        }

        print("CreditExpiryTests passed")
    }
}
