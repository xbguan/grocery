import Foundation

@main
struct SubscriptionAuthTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let privateHome = root.appendingPathComponent("subscription")
        let globalHome = root.appendingPathComponent("global")
        let helper = root.appendingPathComponent("codex")
        let log = root.appendingPathComponent("calls.log")
        try FileManager.default.createDirectory(at: globalHome, withIntermediateDirectories: true)
        try Data("global login".utf8).write(to: globalHome.appendingPathComponent("auth.json"))
        try fakeCodex.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        setenv("CODEX_HOME", globalHome.path, 1)
        setenv("TEST_LOG", log.path, 1)
        defer {
            unsetenv("TEST_LOG")
            unsetenv("CODEX_HOME")
            try? FileManager.default.removeItem(at: root)
        }

        do {
            _ = try SubscriptionReader.read(executable: helper, home: privateHome)
            preconditionFailure("Subscription must not use the global Codex login")
        } catch SubscriptionReadError.login {
        }

        var openedURL: URL?
        let signedIn = try SubscriptionReader.login(executable: helper, home: privateHome) { url in
            openedURL = url
            return true
        }
        precondition(openedURL?.absoluteString == "https://chatgpt.com/auth/test")
        precondition(signedIn.plan == "pro" && signedIn.remainingPercent == 72)
        let refreshed = try SubscriptionReader.read(executable: helper, home: privateHome)
        precondition(refreshed.plan == "pro")

        try SubscriptionReader.logout(executable: helper, home: privateHome)
        do {
            _ = try SubscriptionReader.read(executable: helper, home: privateHome)
            preconditionFailure("Subscription logout must clear only its own login")
        } catch SubscriptionReadError.login {
        }
        let globalCredential = try String(contentsOf: globalHome.appendingPathComponent("auth.json"))
        precondition(globalCredential == "global login")
        let calls = try String(contentsOf: log).replacingOccurrences(of: "\\/", with: "/")
        precondition(calls.contains("account/login/start") && calls.contains("account/logout"))
        precondition(calls.split(separator: "\n").allSatisfy { $0.hasPrefix(privateHome.path + "\t") })
        print("Subscription login isolation OK")
    }

    static let fakeCodex = """
    #!/bin/sh
    while IFS= read -r line; do
      printf '%s\\t%s\\n' "$CODEX_HOME" "$line" >> "$TEST_LOG"
      id=$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"id":([0-9]+).*/\\1/')
      case "$line" in
        *'"method":"initialize"'*)
          printf '{"id":%s,"result":{}}\\n' "$id" ;;
        *'"method":"account'*'login'*'start"'*)
          : > "$CODEX_HOME/auth.json"
          printf '{"id":%s,"result":{"type":"chatgpt","loginId":"test","authUrl":"https://chatgpt.com/auth/test"}}\\n' "$id"
          printf '{"method":"account/login/completed","params":{"loginId":"test","success":true}}\\n' ;;
        *'"method":"account'*'rateLimits'*'read"'*)
          printf '{"id":%s,"result":{"rateLimits":{"primary":{"windowDurationMins":10080,"usedPercent":28}}}}\\n' "$id" ;;
        *'"method":"account'*'read"'*)
          if [ -f "$CODEX_HOME/auth.json" ]; then
            printf '{"id":%s,"result":{"account":{"type":"chatgpt","planType":"pro"}}}\\n' "$id"
          else
            printf '{"id":%s,"result":{"account":null}}\\n' "$id"
          fi ;;
        *'"method":"account'*'logout"'*)
          rm -f "$CODEX_HOME/auth.json"
          printf '{"id":%s,"result":{}}\\n' "$id" ;;
      esac
    done
    """
}
