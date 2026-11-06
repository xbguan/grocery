import Foundation
import Darwin

func listener() -> (Int32, UInt16) {
  let fd = socket(AF_INET, SOCK_STREAM, 0)
  precondition(fd >= 0)
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_addr.s_addr = inet_addr("127.0.0.1")
  let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  precondition(bound == 0 && listen(fd, 1) == 0)
  var length = socklen_t(MemoryLayout<sockaddr_in>.size)
  let named = withUnsafeMutablePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      getsockname(fd, $0, &length)
    }
  }
  precondition(named == 0)
  return (fd, UInt16(bigEndian: address.sin_port))
}

struct Reply {
  let status: Int
  let delay: TimeInterval

  init(_ status: Int, after delay: TimeInterval = 0) {
    self.status = status
    self.delay = delay
  }
}

func sendText(_ fd: Int32, _ text: String) {
  let bytes = Array(text.utf8)
  precondition(bytes.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) } == bytes.count)
}

func readChunk(_ fd: Int32) -> String {
  var bytes = [UInt8](repeating: 0, count: 8192)
  let n = recv(fd, &bytes, bytes.count, 0)
  return n > 0 ? String(decoding: bytes.prefix(n), as: UTF8.self) : ""
}

func verify(_ name: String, request: String = "CONNECT github.com:443", replies: [Reply],
            status: Int, attempt: Int?, elapsed: ClosedRange<TimeInterval>, upstreamHost: String = "127.0.0.1") throws {
  let (upstreamFD, upstreamPort) = listener()
  let (reserved, relayPort) = listener()
  close(reserved)
  var config = Config()
  config.host = upstreamHost
  config.port = Int(upstreamPort)
  config.relayPort = Int(relayPort)
  let relay = RelayServer(cfg: config)
  try relay.start()
  defer { relay.stop() }

  Thread.detachNewThread {
    defer { close(upstreamFD) }
    for (index, reply) in replies.enumerated() {
      var pollFD = pollfd(fd: upstreamFD, events: Int16(POLLIN), revents: 0)
      guard poll(&pollFD, 1, 12000) == 1 else { return }
      let fd = accept(upstreamFD, nil, nil)
      guard fd >= 0 else { return }
      defer { close(fd) }
      var head = ""
      while !head.contains("\r\n\r\n") {
        let chunk = readChunk(fd)
        guard !chunk.isEmpty else { return }
        head += chunk
      }
      precondition(head.hasPrefix(request + " HTTP/1.1"))
      Thread.sleep(forTimeInterval: reply.delay)
      // A zero status simulates an upstream that never sends its response header.
      if reply.status == 0 { return }
      let isTunnel = reply.status == 200
      sendText(fd, "HTTP/1.0 \(reply.status) test\r\nX-Attempt: \(index + 1)\r\n\r\n" + (isTunnel ? "ready" : ""))
      if isTunnel {
        precondition(!head.contains("payload"))
        let payload = readChunk(fd)
        if payload == "payload" { sendText(fd, "echo:" + payload) }
      }
    }
  }

  let client = socket(AF_INET, SOCK_STREAM, 0)
  defer { close(client) }
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = relayPort.bigEndian
  address.sin_addr.s_addr = inet_addr("127.0.0.1")
  let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  precondition(connected == 0)
  var timeout = timeval(tv_sec: 13, tv_usec: 0)
  setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  let started = ProcessInfo.processInfo.systemUptime
  sendText(client, request + " HTTP/1.1\r\nHost: github.com\r\n\r\n" + (status == 200 ? "payload" : ""))
  shutdown(client, SHUT_WR)
  var result = ""
  while true {
    let chunk = readChunk(client)
    if chunk.isEmpty { break }
    result += chunk
  }
  let duration = ProcessInfo.processInfo.systemUptime - started
  guard result.split(separator: " ").dropFirst().first.map(String.init) == String(status),
        attempt.map({ result.contains("X-Attempt: \($0)\r\n") }) ?? true,
        status != 200 || result.hasSuffix("readyecho:payload"),
        elapsed.contains(duration) else {
    fputs("FAIL \(name): \(duration)s, response \(result)\n", stderr)
    exit(1)
  }
  print("PASS \(name) (\(String(format: "%.2f", duration))s)")
}

signal(SIGPIPE, SIG_IGN)
try verify("recovery after one retry", replies: [Reply(502), Reply(200)],
           status: 200, attempt: 2, elapsed: 0.95...2.8, upstreamHost: "localhost")
try verify("recovery on last attempt", request: "CONNECT GitHub.COM:443", replies: [Reply(502), Reply(502), Reply(200)],
           status: 200, attempt: 3, elapsed: 2.95...5)
try verify("retry limit", replies: [Reply(502), Reply(502), Reply(502), Reply(200)],
           status: 502, attempt: 3, elapsed: 2.95...5)
for (request, code) in [("CONNECT api.github.com:443", 502), ("CONNECT github.com:8443", 502),
                        ("GET http://github.com/", 502), ("CONNECT github.com:443", 403),
                        ("CONNECT github.com:443", 407)] {
  try verify("single attempt: "+request+" "+String(code), request: request, replies: [Reply(code), Reply(200)],
             status: code, attempt: 1, elapsed: 0...0.95)
}
try verify("silent upstream", replies: [Reply(0, after: 10)],
           status: 502, attempt: nil, elapsed: 7.7...8.8)
try verify("shared deadline", replies: [Reply(502, after: 5), Reply(0, after: 10)],
           status: 502, attempt: nil, elapsed: 7.7...8.8)
