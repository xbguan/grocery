import Foundation
import Darwin

/// Only display fields from Codex's read-only account protocol.
struct ResetCredit: Identifiable {
    let id: String
    let expiresAt: Date?
}

struct SubscriptionSnapshot {
    var email: String?
    var plan: String?
    var remainingPercent: Int?
    var weeklyReset: Date?
    var resetCredits: Int?
    var resetCreditDetails: [ResetCredit] = []
    var usageUnavailable = false
    let fetchedAt = Date()

    var maskedEmail: String? {
        guard let email else { return nil }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        let prefix = parts[0].prefix(min(2, parts[0].count - 1))
        return "\(prefix)***@\(parts[1])"
    }

    var displayPlan: String? {
        switch plan?.lowercased() {
        case "free": return "Free"
        case "plus": return "Plus"
        case "pro", "prolite": return "Pro"
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
    case login = "请在订阅设置中登录 ChatGPT 账号。"
    case browser = "无法打开 ChatGPT 登录页面，请重试。"
    case service = "暂时无法读取 Codex 订阅数据，请检查网络和 Codex 版本后再刷新。"
    case timeout = "订阅读取超时，请稍后刷新。"
    var errorDescription: String? { rawValue }
}

enum SubscriptionReader {
    private static var defaultHome: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenAIApiDashboard/SubscriptionCodex", isDirectory: true)
    }

    private static func codexURL() throws -> URL {
        let paths = [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        ]
        guard let path = paths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw SubscriptionReadError.missing
        }
        return URL(fileURLWithPath: path)
    }

    static func read(executable: URL? = nil, home: URL? = nil) throws -> SubscriptionSnapshot {
        let session = try CodexSession(executable: executable ?? codexURL(), home: home ?? defaultHome)
        return try session.snapshot()
    }

    static func login(executable: URL? = nil, home: URL? = nil,
                      openURL: (URL) -> Bool) throws -> SubscriptionSnapshot {
        let session = try CodexSession(executable: executable ?? codexURL(), home: home ?? defaultHome)
        try session.login(openURL: openURL)
        return try session.snapshot()
    }

    static func logout(executable: URL? = nil, home: URL? = nil) throws {
        let session = try CodexSession(executable: executable ?? codexURL(), home: home ?? defaultHome)
        _ = try session.request("account/logout")
    }
}

private final class CodexSession {
    private let process: Process
    private let writer: FileHandle
    private let reader: FileHandle
    private var pending = Data()
    private var nextID = 1
    private var loginCompletion: [String: Any]?

    init(executable: URL, home: URL) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        // Never trigger a Keychain prompt from the helper or load project-local settings.
        process.arguments = ["app-server", "-c", "cli_auth_credentials_store=\"file\"",
                             "-c", "mcp_oauth_credentials_store=\"file\""]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["CODEX_HOME"] = home.path
        env.removeValue(forKey: "OPENAI_API_KEY")
        env.removeValue(forKey: "CODEX_API_KEY")
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        writer = input.fileHandleForWriting
        reader = output.fileHandleForReading
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        _ = try request("initialize", [
            "clientInfo": ["name": "openai_dashboard", "version": "1"],
            "capabilities": ["experimentalApi": true]
        ])
        try send(["method": "initialized"])
    }

    deinit {
        try? writer.close()
        if process.isRunning { process.terminate() }
        try? reader.close()
    }

    private func send(_ object: [String: Any]) throws {
        var bytes = try JSONSerialization.data(withJSONObject: object)
        bytes.append(10)
        try writer.write(contentsOf: bytes)
    }

    private func readMessage(until deadline: TimeInterval) throws -> [String: Any] {
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let end = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: end)
                pending.removeSubrange(...end)
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw SubscriptionReadError.service
                }
                return message
            }
            var fd = pollfd(fd: reader.fileDescriptor, events: Int16(POLLIN), revents: 0)
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

    @discardableResult
    func request(_ method: String, _ params: [String: Any]? = nil) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        try send(message)
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while true {
            let message = try readMessage(until: deadline)
            if message["method"] as? String == "account/login/completed" {
                loginCompletion = message["params"] as? [String: Any]
            }
            guard message["id"] as? Int == id else { continue }
            guard let result = message["result"] as? [String: Any] else {
                throw SubscriptionReadError.service
            }
            return result
        }
    }

    func login(openURL: (URL) -> Bool) throws {
        let result = try request("account/login/start", ["type": "chatgpt"])
        guard let raw = result["authUrl"] as? String, let url = URL(string: raw),
              url.scheme == "https", let loginID = result["loginId"] as? String else {
            throw SubscriptionReadError.service
        }
        guard openURL(url) else { throw SubscriptionReadError.browser }
        let deadline = ProcessInfo.processInfo.systemUptime + 300
        while loginCompletion == nil {
            let message = try readMessage(until: deadline)
            if message["method"] as? String == "account/login/completed" {
                loginCompletion = message["params"] as? [String: Any]
            }
        }
        guard loginCompletion?["loginId"] as? String == loginID,
              loginCompletion?["success"] as? Bool == true else {
            throw SubscriptionReadError.login
        }
    }

    func snapshot() throws -> SubscriptionSnapshot {
        let account = try request("account/read", ["refreshToken": false])["account"] as? [String: Any]
        guard account?["type"] as? String == "chatgpt" else { throw SubscriptionReadError.login }
        var snapshot = SubscriptionSnapshot(email: account?["email"] as? String, plan: account?["planType"] as? String)
        do {
            snapshot.apply(try request("account/rateLimits/read", ["excludeResetCreditDetails": false]))
        } catch {
            snapshot.usageUnavailable = true
        }
        return snapshot
    }
}
