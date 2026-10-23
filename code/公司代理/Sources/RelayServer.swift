import Foundation
import Darwin

/// 本地免认证 HTTP 代理中继
/// 监听 127.0.0.1:<relayPort>，转发到公司 3proxy 并自动注入 Proxy-Authorization。
/// 存在的理由：macOS 系统代理里保存的代理凭据 Chromium 不读，会反复弹「登录以访问此站点」。
final class RelayServer {
    private var cfg: Config
    private var listenFD: Int32 = -1
    private var running = false
    private let lock = NSLock()

    private(set) var lastError: String?
    var onFatal: ((String) -> Void)?

    init(cfg: Config) { self.cfg = cfg }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    func update(cfg: Config) {
        lock.lock(); self.cfg = cfg; lock.unlock()
    }

    // MARK: 生命周期

    func start() throws {
        stop()
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw err("socket() 失败") }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(cfg.relayPort).bigEndian
        addr.sin_addr.s_addr = inet_addr(cfg.relayHost == "localhost" ? "127.0.0.1" : cfg.relayHost)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let e = String(cString: strerror(errno))
            close(fd)
            throw err("端口 \(cfg.relayPort) 绑定失败：\(e)")
        }
        guard listen(fd, 256) == 0 else {
            close(fd)
            throw err("listen() 失败")
        }

        listenFD = fd
        lock.lock(); running = true; lock.unlock()

        let t = Thread { [weak self] in self?.acceptLoop(fd) }
        t.name = "corp-proxy-relay-accept"
        t.stackSize = 512 * 1024
        t.start()
    }

    func stop() {
        lock.lock()
        let wasRunning = running
        running = false
        let fd = listenFD
        listenFD = -1
        lock.unlock()

        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
        _ = wasRunning
    }

    private func err(_ msg: String) -> NSError {
        NSError(domain: "CorpProxyRelay", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    // MARK: 接受连接

    private func acceptLoop(_ fd: Int32) {
        while isRunning {
            let cfd = accept(fd, nil, nil)
            if cfd < 0 {
                if !isRunning { break }
                if errno == EINTR || errno == ECONNABORTED { continue }
                usleep(50_000)
                continue
            }
            var one: Int32 = 1
            setsockopt(cfd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))

            let t = Thread { [weak self] in self?.handle(cfd) }
            t.name = "corp-proxy-relay-conn"
            t.stackSize = 512 * 1024
            t.start()
        }
    }

    // MARK: 单连接处理

    private func handle(_ client: Int32) {
        lock.lock()
        let conf = cfg
        lock.unlock()

        defer { close(client) }

        var tv = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        guard let (head, leftover) = readHead(client) else { return }
        guard let text = String(data: head, encoding: .isoLatin1) else { return }
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first else { return }
        let parts = first.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return }
        let method = parts[0].uppercased()
        let target = parts[1]

        let isConnect = method == "CONNECT"
        let upstream = connectTimeout(conf.host, UInt16(conf.port), timeout: 8)
        guard upstream >= 0 else {
            _ = writeAll(client, Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
            return
        }
        defer { close(upstream) }

        var one: Int32 = 1
        setsockopt(upstream, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        var zero = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(upstream, SOL_SOCKET, SO_RCVTIMEO, &zero, socklen_t(MemoryLayout<timeval>.size))

        let auth = "Proxy-Authorization: Basic "
            + Data("\(conf.user):\(conf.pass)".utf8).base64EncodedString()

        // 重组请求头：注入认证，去掉已有认证/长连接头
        var rebuilt: [String] = [first, auth]
        if isConnect {
            rebuilt.append("Proxy-Connection: keep-alive")
        } else {
            rebuilt.append("Connection: close")
        }
        for ln in lines.dropFirst() where !ln.isEmpty {
            let low = ln.lowercased()
            if low.hasPrefix("proxy-authorization:") { continue }
            if low.hasPrefix("proxy-connection:") { continue }
            if low.hasPrefix("connection:") && !isConnect { continue }
            rebuilt.append(ln)
        }
        let blob = Data((rebuilt.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        guard writeAll(upstream, blob) else { return }

        if isConnect {
            guard let (resp, extra) = readHead(upstream, limit: 32 * 1024) else { return }
            guard writeAll(client, resp) else { return }
            let statusLine = String(data: resp, encoding: .isoLatin1)?.components(separatedBy: "\r\n").first ?? ""
            guard statusLine.contains(" 200") else { return }
            if !leftover.isEmpty { _ = writeAll(upstream, leftover) }
            if !extra.isEmpty { _ = writeAll(client, extra) }
        } else {
            if !leftover.isEmpty { _ = writeAll(upstream, leftover) }
        }

        splice(client, upstream)
    }

    // MARK: 双向搬运

    /// 每条连接两个专用线程（不做 GCD 线程池排队）。
    /// 早期版本用 DispatchQueue.global()，浏览器几十条常驻隧道就会把池子占满，
    /// 新请求只能排队 → 表现为「网页和 CLI 都变慢」。
    private func splice(_ a: Int32, _ b: Int32) {
        var z = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(a, SOL_SOCKET, SO_RCVTIMEO, &z, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(b, SOL_SOCKET, SO_RCVTIMEO, &z, socklen_t(MemoryLayout<timeval>.size))

        let sem = DispatchSemaphore(value: 0)
        for (from, to) in [(a, b), (b, a)] {
            let t = Thread { [weak self] in
                self?.pump(from, to)
                shutdown(to, SHUT_WR)
                sem.signal()
            }
            t.name = "corp-proxy-relay-pump"
            t.stackSize = 256 * 1024
            t.start()
        }
        sem.wait()
        sem.wait()
    }

    private func pump(_ from: Int32, _ to: Int32) {
        var buf = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = recv(from, &buf, buf.count, 0)
            if n <= 0 { break }
            guard writeAll(to, buf, count: n) else { break }
        }
    }

    // MARK: 底层 I/O

    @discardableResult
    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var ok = true
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var off = 0
            while off < raw.count {
                let n = send(fd, base.advanced(by: off), raw.count - off, 0)
                if n <= 0 { ok = false; return }
                off += n
            }
        }
        return ok
    }

    @discardableResult
    private func writeAll(_ fd: Int32, _ buf: [UInt8], count: Int) -> Bool {
        var ok = true
        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var off = 0
            while off < count {
                let n = send(fd, base.advanced(by: off), count - off, 0)
                if n <= 0 { ok = false; return }
                off += n
            }
        }
        return ok
    }

    /// 读到 \r\n\r\n 为止，返回（头，多读出来的字节）
    private func readHead(_ fd: Int32, limit: Int = 64 * 1024) -> (Data, Data)? {
        var acc = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while acc.count < limit {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { return nil }
            acc.append(contentsOf: buf[0..<n])
            if let r = acc.range(of: Data("\r\n\r\n".utf8)) {
                let headEnd = r.upperBound
                return (acc.subdata(in: acc.startIndex..<headEnd),
                        acc.subdata(in: headEnd..<acc.endIndex))
            }
        }
        return nil
    }

    /// 带超时的 TCP 连接
    private func connectTimeout(_ host: String, _ port: UInt16, timeout: TimeInterval) -> Int32 {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil,
                             ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let head = res else { return -1 }
        defer { freeaddrinfo(head) }

        var ptr: UnsafeMutablePointer<addrinfo>? = head
        while let ai = ptr {
            let fd = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
            if fd >= 0 {
                let flags = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                let r = connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen)
                if r == 0 {
                    _ = fcntl(fd, F_SETFL, flags)
                    return fd
                }
                if errno == EINPROGRESS {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    let sel = poll(&pfd, 1, Int32(timeout * 1000))
                    if sel > 0 {
                        var e: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(fd, SOL_SOCKET, SO_ERROR, &e, &len)
                        if e == 0 {
                            _ = fcntl(fd, F_SETFL, flags)
                            return fd
                        }
                    }
                }
                close(fd)
            }
            ptr = ai.pointee.ai_next
        }
        return -1
    }
}
