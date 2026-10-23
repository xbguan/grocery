import Foundation

// MARK: - VPN 接入方式

enum VPNMode: String, CaseIterable {
    case auto
    case hdvpn
    case l2tp

    var title: String {
        switch self {
        case .auto:  return "自动检测（推荐）"
        case .hdvpn: return "HD-VPN 客户端（ppp0 隧道）"
        case .l2tp:  return "路由器 L2TP（无需客户端）"
        }
    }

    var shortTitle: String {
        switch self {
        case .auto:  return "自动"
        case .hdvpn: return "HD-VPN"
        case .l2tp:  return "路由器 L2TP"
        }
    }
}

// MARK: - 配置

struct Config {
    var host: String = "172.17.2.15"
    var port: Int = 7887
    var user: String = "admin"
    var pass: String = ""
    var relayHost: String = "127.0.0.1"
    var relayPort: Int = 7899
    var bypass: String = "127.0.0.1 localhost *.local 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 *.hd123.com gitlab.hd123.com"
    var vpnMode: VPNMode = .auto

    static var dirPath: String { NSString(string: "~/.config/corp-proxy").expandingTildeInPath }
    static var filePath: String { dirPath + "/config" }
    static var legacyCLIPath: String { NSString(string: "~/.local/bin/corp-proxy").expandingTildeInPath }

    var bypassList: [String] {
        bypass.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    var relayURL: String { "http://\(relayHost):\(relayPort)" }
    var upstreamURL: String { "http://\(host):\(port)" }
    var upstreamURLWithAuth: String {
        user.isEmpty ? upstreamURL : "http://\(user):\(pass)@\(host):\(port)"
    }

    // MARK: 读写

    static func load() -> Config {
        var c = Config()
        guard let text = try? String(contentsOfFile: filePath, encoding: .utf8) else { return c }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if val.count >= 2, (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            switch key {
            case "CORP_HOST":   if !val.isEmpty { c.host = val }
            case "CORP_PORT":   if let n = Int(val), n > 0 { c.port = n }
            case "CORP_USER":   c.user = val
            case "CORP_PASS":   c.pass = val
            case "RELAY_HOST":  if !val.isEmpty { c.relayHost = val }
            case "RELAY_PORT":  if let n = Int(val), n > 0 { c.relayPort = n }
            case "BYPASS_DOMAINS": if !val.isEmpty { c.bypass = val }
            case "VPN_MODE":    c.vpnMode = VPNMode(rawValue: val.lowercased()) ?? .auto
            default: break
            }
        }
        return c
    }

    func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: Config.dirPath, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let body = """
        # 公司代理配置 —— 由「公司代理」App 读写（chmod 600，勿公开）
        # 修改后无需重启 App：设置窗口点「保存」即会重载并重启本地中继。
        CORP_HOST=\(Self.quote(host))
        CORP_PORT=\(port)
        CORP_USER=\(Self.quote(user))
        CORP_PASS=\(Self.quote(pass))

        # 本地免认证中继（浏览器/系统代理指向它，由它代填凭据）
        RELAY_HOST=\(Self.quote(relayHost))
        RELAY_PORT=\(relayPort)

        # 直连白名单（不走代理）
        BYPASS_DOMAINS=\(Self.quote(bypass))

        # VPN 接入方式：auto | hdvpn | l2tp
        VPN_MODE=\(vpnMode.rawValue)

        """
        try body.write(toFile: Config.filePath, atomically: true, encoding: .utf8)
        chmod(Config.filePath, 0o600)
    }

    private static func quote(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        if s.contains(" ") || s.contains("#") || s.contains("\"") || s.contains("'") || s.contains("$") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return s
    }
}
