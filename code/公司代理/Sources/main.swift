import Cocoa
import Darwin

// 中继里用 send()，避免对端关闭时被 SIGPIPE 杀掉
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 启动瞬间就按配置决定激活策略，避免先闪一下 Dock 图标
let startupCfg = Config.load()
app.setActivationPolicy(startupCfg.showInDock ? .regular : .accessory)
app.run()
