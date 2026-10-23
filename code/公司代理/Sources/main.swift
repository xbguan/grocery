import Cocoa
import Darwin

// 中继里用 send()，避免对端关闭时被 SIGPIPE 杀掉
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
