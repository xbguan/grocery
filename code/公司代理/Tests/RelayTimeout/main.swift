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

let (upstreamFD, upstreamPort) = listener()
let (unusedRelayFD, relayPort) = listener()
close(unusedRelayFD)
let accepted = DispatchSemaphore(value: 0)
let upstreamThread = Thread {
  let connection = accept(upstreamFD, nil, nil)
  guard connection >= 0 else { return }
  var buffer = [UInt8](repeating: 0, count: 4096)
  _ = recv(connection, &buffer, buffer.count, 0)
  accepted.signal()
  Thread.sleep(forTimeInterval: 15)
  close(connection)
}
upstreamThread.start()

var config = Config()
config.host = "127.0.0.1"
config.port = Int(upstreamPort)
config.relayPort = Int(relayPort)
let relay = RelayServer(cfg: config)
try relay.start()

let client = socket(AF_INET, SOCK_STREAM, 0)
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
var timeout = timeval(tv_sec: 12, tv_usec: 0)
setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
let request = Array("CONNECT github.com:443 HTTP/1.1\r\nHost: github.com:443\r\n\r\n".utf8)
_ = request.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
precondition(accepted.wait(timeout: .now() + 2) == .success)

var response = [UInt8](repeating: 0, count: 4096)
let started = Date()
let count = recv(client, &response, response.count, 0)
let elapsed = Date().timeIntervalSince(started)
let status = count > 0 ? String(decoding: response[0..<count], as: UTF8.self) : ""
close(client)
relay.stop()
close(upstreamFD)

guard status.hasPrefix("HTTP/1.1 502 Bad Gateway") && elapsed < 12 else {
  fputs("FAIL: upstream stayed silent; response=\(status.prefix(80)), elapsed=\(elapsed)\n", stderr)
  exit(1)
}
print("PASS: silent upstream returned 502 in \(elapsed) seconds")
