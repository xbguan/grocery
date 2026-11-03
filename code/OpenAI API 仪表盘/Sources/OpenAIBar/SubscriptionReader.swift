import Foundation
import Darwin

/// Only display fields from Codex's read-only account protocol.
struct ResetCredit: Identifiable {
    let id: String
    let expiresAt: Date?
}

struct SubscriptionSnapshot {
    var plan: String?
    var remainingPercent: Int?
    var weeklyReset: Date?
    var resetCredits: Int?
    var resetCreditDetails: [ResetCredit] = []
    var usageUnavailable = false
    let fetchedAt = Date()

    var displayPlan: String? {
        switch plan?.lowercased() {
        case "free": return "Free"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        default: return nil
        }
    }

    mutating func apply(_ result: [String: Any]) {
        let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        let legacy = result["rateLimits"] as? [String: Any]
        let legacyID = legacy?["limitId"] as? String
        let bucket = buckets?["codex"] ?? (legacyID == nil || legacyID == "codex" ? legacy : nil)
        let week = ["primary", "secondary"].compactMap { bucket?[$0] as? [String: Any] }
            .first { $0["windowDurationMins"] as? Int == 7 * 24 * 60 }
        if let used = week?["usedPercent"] as? Int, (0...100).contains(used) {
            remainingPercent = 100 - used
        }
        if let timestamp = week?["resetsAt"] as? Double, timestamp > 0 {
            weeklyReset = Date(timeIntervalSince1970: timestamp)
        }
        let reset = result["rateLimitResetCredits"] as? [String: Any]
        if let count = reset?["availableCount"] as? Int,
           count >= 0 { resetCredits = count }
        if let credits = reset?["credits"] as? [[String: Any]] {
            resetCreditDetails = credits.compactMap { credit in
                guard credit["status"] as? String == "available",
                      let id = credit["id"] as? String else { return nil }
                let timestamp = (credit["expiresAt"] as? NSNumber)?.doubleValue
                let expiry = timestamp.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                return ResetCredit(id: id, expiresAt: expiry)
            }.sorted {
                if $0.expiresAt == $1.expiresAt { return $0.id < $1.id }
                return ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
            }
        }
    }
}

enum SubscriptionReadError: String, LocalizedError {
    case missing = "未找到本机 Codex 程序。请安装 Codex CLI、Codex 或 ChatGPT 应用。"
    case login = "请先在本机 Codex 中使用 ChatGPT 账号登录，再刷新。只支持文件存储的 Codex 登录凭据。"
    case service = "暂时无法读取 Codex 订阅数据，请检查网络和 Codex 版本后再刷新。"
    case timeout = "订阅读取超时，请稍后刷新。"
    var errorDescription: String? { rawValue }
}

enum SubscriptionReader {
    static func read() throws -> SubscriptionSnapshot {
        let paths = [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        ]
        guard let path = paths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw SubscriptionReadError.missing
        }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        // Never trigger a Keychain prompt from the helper or load project-local settings.
        process.arguments = ["app-server", "-c", "cli_auth_credentials_store=\"file\"",
                             "-c", "mcp_oauth_credentials_store=\"file\""]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let writer = input.fileHandleForWriting
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        defer {
            try? writer.close()
            if process.isRunning { process.terminate() }
            try? output.fileHandleForReading.close()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        var pending = Data()
        func send(_ object: [String: Any]) throws {
            var bytes = try JSONSerialization.data(withJSONObject: object)
            bytes.append(10)
            try writer.write(contentsOf: bytes)
        }
        func request(_ id: Int, _ method: String, _ params: [String: Any]) throws -> [String: Any] {
            try send(["id": id, "method": method, "params": params])
            while ProcessInfo.processInfo.systemUptime < deadline {
                if let end = pending.firstIndex(of: 10) {
                    let line = pending.prefix(upTo: end)
                    pending.removeSubrange(...end)
                    guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                          message["id"] as? Int == id else { continue }
                    guard let result = message["result"] as? [String: Any] else {
                        throw SubscriptionReadError.service
                    }
                    return result
                }
                var fd = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let milliseconds = Int32(max(1, (deadline - ProcessInfo.processInfo.systemUptime) * 1000))
                let ready = poll(&fd, 1, milliseconds)
                if ready == 0 { throw SubscriptionReadError.timeout }
                if ready < 0 && errno == EINTR { continue }
                guard ready > 0, pending.count < 2_000_000 else { throw SubscriptionReadError.service }
                var buffer = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(fd.fd, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SubscriptionReadError.service }
                pending.append(contentsOf: buffer.prefix(count))
            }
            throw SubscriptionReadError.timeout
        }
        _ = try request(1, "initialize", [
            "clientInfo": ["name": "openai_dashboard", "version": "1"],
            "capabilities": ["experimentalApi": true]
        ])
        try send(["method": "initialized"])
        let account = try request(2, "account/read", ["refreshToken": false])["account"] as? [String: Any]
        guard account?["type"] as? String == "chatgpt" else { throw SubscriptionReadError.login }
        var snapshot = SubscriptionSnapshot(plan: account?["planType"] as? String)
        do {
            snapshot.apply(try request(3, "account/rateLimits/read", ["excludeResetCreditDetails": false]))
        } catch {
            snapshot.usageUnavailable = true
        }
        return snapshot
    }
}
