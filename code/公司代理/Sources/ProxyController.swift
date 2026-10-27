import Foundation
import SystemConfiguration
import Darwin

// MARK: - 壳命令

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 20) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }

        // 边读边等，避免子进程写满管道阻塞
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        _ = timeout
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func networksetup(_ args: [String]) -> (Int32, String) {
        run("/usr/sbin/networksetup", args)
    }

    /// TCP 探活
    static func tcpAlive(_ host: String, _ port: UInt16, timeout: TimeInterval = 3) -> Bool {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil,
                             ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let head = res else { return false }
        defer { freeaddrinfo(head) }

        var ptr: UnsafeMutablePointer<addrinfo>? = head
        while let ai = ptr {
            let fd = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
            if fd >= 0 {
                let flags = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                let r = connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen)
                if r == 0 {
                    close(fd)
                    return true
                }
                if errno == EINPROGRESS {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    let sel = poll(&pfd, 1, Int32(timeout * 1000))
                    if sel > 0 {
                        var err: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
                        close(fd)
                        if err == 0 { return true }
                    } else {
                        close(fd)
                    }
                } else {
                    close(fd)
                }
            }
            ptr = ai.pointee.ai_next
        }
        return false
    }
}

// MARK: - 代理控制器

final class ProxyController {
    var cfg: Config

    /// 中继是否由本 App 托管运行中（由 AppDelegate 维护）
    var relayRunning: () -> Bool = { false }

    init(_ cfg: Config) { self.cfg = cfg }

    // MARK: 环境探测

    /// ppp0 是否拿到地址（HD-VPN 客户端在线）
    func ppp0Up() -> Bool {
        let (_, out) = Shell.run("/sbin/ifconfig", ["ppp0"])
        return out.contains("inet ")
    }

    /// 解析后的实际模式
    func resolvedMode() -> VPNMode {
        switch cfg.vpnMode {
        case .auto:  return ppp0Up() ? .hdvpn : .l2tp
        case .hdvpn: return .hdvpn
        case .l2tp:  return .l2tp
        }
    }

    func primaryIface() -> String {
        guard let store = SCDynamicStoreCreate(nil, "corpproxy" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let iface = dict["PrimaryInterface"] as? String else { return "?" }
        return iface
    }

    /// 系统里所有可用网络服务（去掉被禁用的，那些以 * 开头）
    func allServices() -> [String] {
        let (_, out) = Shell.networksetup(["-listallnetworkservices"])
        return out.components(separatedBy: .newlines)
            .dropFirst()                        // 首行是说明文字
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
    }

    /// 需要挂代理的服务：按 VPN 接入方式裁剪
    func servicesToSet() -> [String] {
        let all = allServices()
        switch resolvedMode() {
        case .l2tp:
            // 路由器已做 L2TP，本机没有 VPN 虚拟服务，只需物理网卡
            return all.filter { $0 != "VPN" }
        case .hdvpn, .auto:
            return all
        }
    }

    // MARK: 系统代理状态

    func systemProxy() -> (on: Bool, address: String) {
        guard let d = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return (false, "") }
        let httpOn = (d["HTTPEnable"] as? Int ?? 0) == 1
        let httpsOn = (d["HTTPSEnable"] as? Int ?? 0) == 1
        let host = (d["HTTPProxy"] as? String) ?? (d["HTTPSProxy"] as? String) ?? ""
        let port = (d["HTTPPort"] as? Int) ?? (d["HTTPSPort"] as? Int) ?? 0
        let on = httpOn || httpsOn
        return (on, on ? "\(host):\(port)" : "")
    }

    // MARK: 开关

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func hookHint(_ mode: VPNMode) -> String {
        switch mode {
        case .l2tp:
            return "路由器 L2TP 未接通或内网不可达：请确认路由器已建立 L2TP 到公司，且本机在公司内网路由上。"
        case .hdvpn:
            return "HD-VPN 客户端未连接（ppp0 无地址）：请先打开 HD-VPN.app 连上公司 VPN。"
        case .auto:
            return "内网不可达：HD-VPN 未连接，或路由器 L2TP 未接通。"
        }
    }

    @discardableResult
    func turnOn(allowEmptyCredentials: Bool = false) -> Result<String, Failure> {
        let mode = resolvedMode()

        // 1) 凭据检查：空凭据挂上去，公司 3proxy 会回 407，浏览器就会不停弹认证框
        if !cfg.hasCredentials && !allowEmptyCredentials {
            return .failure(Failure(message:
                "还没有填写代理用户名/密码。\n\n空凭据连公司 3proxy 会被拒绝（407），浏览器会反复弹「输入代理用户名和密码」。\n请先在「设置…」里填写后再启用。"))
        }

        // 2) 必须经本地中继。直连公司上游时，系统代理里存的凭据 Chromium 不读，
        //    页面必然弹认证框 —— 所以这里不再回退到直连。
        guard relayRunning() else {
            return .failure(Failure(message:
                "本地中继 127.0.0.1:\(cfg.relayPort) 还没就绪。\n\n为避免浏览器弹代理认证框，本次没有改动系统代理。\n请等几秒重试；若一直如此，重启 App 或检查端口是否被占用。"))
        }

        guard Shell.tcpAlive(cfg.host, UInt16(cfg.port), timeout: 3) else {
            return .failure(Failure(message: "连不上公司代理 \(cfg.host):\(cfg.port)\n\n\(hookHint(mode))"))
        }

        let useRelay = true
        let proxyHost = cfg.relayHost
        let proxyPort = cfg.relayPort
        let services = servicesToSet()
        var applied: [String] = []

        for s in services {
            let (rc, _) = Shell.networksetup(["-getwebproxy", s])
            guard rc == 0 else { continue }     // 服务不存在
            Shell.networksetup(["-setwebproxy", s, proxyHost, String(proxyPort)])
            Shell.networksetup(["-setsecurewebproxy", s, proxyHost, String(proxyPort)])
            Shell.networksetup(["-setproxybypassdomains", s] + cfg.bypassList)
            applied.append(s)
        }

        // networksetup 的 setwebproxy 会顺带打开开关；显式保证一次
        Thread.sleep(forTimeInterval: 0.8)

        rewriteCodexEnv(enabled: true, viaRelay: useRelay)

        guard !applied.isEmpty else {
            return .failure(Failure(message: "没有找到可设置代理的网络服务（networksetup 报错）。"))
        }

        var lines: [String] = []
        lines.append("接入方式：\(mode.shortTitle)\(cfg.vpnMode == .auto ? "（自动检测）" : "")")
        lines.append("代理地址：\(proxyHost):\(proxyPort)" + (useRelay ? "（经本地中继，浏览器不会弹认证框）" : "（直连公司代理，浏览器可能要求登录）"))
        lines.append("已设置 \(applied.count) 个网络服务：\(applied.joined(separator: "、"))")
        lines.append("Codex CLI：~/.codex/.env 已写入代理")

        let st = systemProxy()
        if st.on {
            lines.append("生效确认：主接口 \(primaryIface()) 已挂代理 \(st.address)")
        } else {
            lines.append("⚠︎ scutil 显示系统代理未生效，主接口为 \(primaryIface())")
        }

        let code = curlStatus(viaRelay: useRelay)
        lines.append(code == "401" ? "出口验证：chatgpt.com → 401（正常）"
                                   : "出口验证：返回 \(code.isEmpty ? "000" : code)（可能异常）")
        return .success(lines.joined(separator: "\n"))
    }

    @discardableResult
    func turnOff() -> Result<String, Failure> {
        // 关闭时清理得比开启更宽：包括所有历史遗留服务
        let candidates = allServices() + ["VPN", "Ethernet", "USB 10/100/1000 LAN", "Thunderbolt Bridge", "iPhone USB"]
        var seen = Set<String>()
        var touched: [String] = []
        for s in candidates where !seen.contains(s) {
            seen.insert(s)
            let (rc, _) = Shell.networksetup(["-getwebproxy", s])
            guard rc == 0 else { continue }
            Shell.networksetup(["-setwebproxystate", s, "off"])
            Shell.networksetup(["-setsecurewebproxystate", s, "off"])
            Shell.networksetup(["-setsocksfirewallproxystate", s, "off"])
            touched.append(s)
        }
        Thread.sleep(forTimeInterval: 0.6)
        rewriteCodexEnv(enabled: false, viaRelay: false)
        return .success("系统代理已关闭（\(touched.count) 个网络服务）\nCodex CLI：已改为直连")
    }

    /// 走代理验证出口；401 表示 OpenAI 认这个 IP
    private func curlStatus(viaRelay: Bool) -> String {
        let proxy = viaRelay ? cfg.relayURL : cfg.upstreamURLWithAuth
        let (rc, out) = Shell.run("/usr/bin/curl",
                                  ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "12",
                                   "-x", proxy, "https://chatgpt.com/backend-api/me"], timeout: 18)
        return rc == 0 ? out.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    // MARK: Codex .env

    func rewriteCodexEnv(enabled: Bool, viaRelay: Bool) {
        let path = NSString(string: "~/.codex/.env").expandingTildeInPath
        guard let original = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        try? original.write(toFile: path + ".corpbak", atomically: true, encoding: .utf8)

        var kept: [String] = []
        for line in original.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            let probe = t.hasPrefix("#") ? String(t.dropFirst()).trimmingCharacters(in: .whitespaces) : t
            let low = probe.lowercased()
            if low.hasPrefix("http_proxy=") || low.hasPrefix("https_proxy=") || low.hasPrefix("all_proxy=") { continue }
            if t.hasPrefix("# --- corp-proxy:") { continue }
            kept.append(line)
        }
        while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty { kept.removeLast() }

        if enabled {
            let url = viaRelay ? cfg.relayURL : cfg.upstreamURLWithAuth
            let shown = viaRelay ? "\(cfg.relayHost):\(cfg.relayPort) relay" : "\(cfg.host):\(cfg.port)"
            kept.append("")
            kept.append("# --- corp-proxy: ON (\(shown)) ---")
            kept.append("HTTP_PROXY=\(url)")
            kept.append("HTTPS_PROXY=\(url)")
            kept.append("ALL_PROXY=\(url)")
        } else {
            kept.append("")
            kept.append("# --- corp-proxy: OFF -> Codex 直连，未配置代理 ---")
        }

        try? (kept.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o600)
    }

    // MARK: 状态文本

    func statusText() -> String {
        let mode = resolvedMode()
        let st = systemProxy()
        var out: [String] = []
        out.append("主接口：\(primaryIface())")
        out.append("接入方式：\(mode.shortTitle)（配置为 \(cfg.vpnMode.shortTitle)）")

        switch mode {
        case .hdvpn:
            out.append("ppp0 隧道：\(ppp0Up() ? "在线" : "断开")")
        case .l2tp:
            out.append("路由器 L2TP：\(Shell.tcpAlive(cfg.host, UInt16(cfg.port)) ? "内网可达" : "内网不可达")")
        case .auto:
            out.append("ppp0 隧道：\(ppp0Up() ? "在线" : "断开")")
        }

        out.append("")
        out.append(st.on ? "系统代理：已开启 → \(st.address)" : "系统代理：已关闭")
        out.append(relayRunning() ? "本地中继：\(cfg.relayHost):\(cfg.relayPort) 运行中" : "本地中继：未运行")
        let envOn = (try? String(contentsOfFile: NSString(string: "~/.codex/.env").expandingTildeInPath, encoding: .utf8))?
            .contains("HTTPS_PROXY=http://") ?? false
        out.append("Codex .env：\(envOn ? "指向代理" : "直连")")
        out.append("")
        out.append("公司代理：\(cfg.host):\(cfg.port)" + (Shell.tcpAlive(cfg.host, UInt16(cfg.port), timeout: 2) ? "（可连接）" : "（不通）"))
        out.append("用户：\(cfg.user)")
        out.append("中继端口：\(cfg.relayPort)")
        out.append("服务：\(servicesToSet().joined(separator: "、"))")
        return out.joined(separator: "\n")
    }
}
