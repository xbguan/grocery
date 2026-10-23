import Foundation

/// 卸载清理：把 App 留下的一切都收干净
enum Uninstaller {

    static func targets(includeLegacy: Bool) -> [(label: String, path: String)] {
        let home = NSHomeDirectory()
        var list: [(String, String)] = [
            ("配置目录", home + "/.config/corp-proxy"),
            ("中继日志", home + "/Library/Logs/corp-proxy-relay.log"),
            ("开机自启(LaunchAgent)", home + "/Library/LaunchAgents/local.xbguan.corpproxy.plist"),
            ("偏好设置", home + "/Library/Preferences/local.xbguan.corpproxy.plist"),
            ("窗口状态", home + "/Library/Saved Application State/local.xbguan.corpproxy.savedState"),
            ("缓存", home + "/Library/Caches/local.xbguan.corpproxy"),
            ("网络存储", home + "/Library/HTTPStorages/local.xbguan.corpproxy"),
            ("网络存储(Cookies)", home + "/Library/HTTPStorages/local.xbguan.corpproxy.binarycookies"),
        ]
        if includeLegacy {
            list += [
                ("旧版中继自启项", home + "/Library/LaunchAgents/local.xbguan.corpproxy.relay.plist"),
                ("旧版命令行脚本", home + "/.local/bin/corp-proxy"),
                ("旧版中继脚本", home + "/.local/bin/corp-proxy-relay"),
                ("命令行软链", "/usr/local/bin/corp-proxy"),
            ]
        }
        return list
    }

    /// 后台执行；progress 回主线程回调，done 回主线程回调
    static func perform(controller: ProxyController,
                        relay: RelayServer,
                        includeLegacy: Bool,
                        progress: @escaping (String) -> Void,
                        done: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            func step(_ text: String) { DispatchQueue.main.async { progress(text) } }

            step("关闭系统代理，恢复直连…")
            _ = controller.turnOff()

            step("停止本地中继…")
            relay.stop()

            step("注销开机自启…")
            LoginItem.disable()

            step("删除配置、日志与残留文件…")
            let fm = FileManager.default
            var removed: [String] = []
            var failed: [String] = []
            for item in targets(includeLegacy: includeLegacy) {
                guard fm.fileExists(atPath: item.path) else { continue }
                do {
                    try fm.removeItem(atPath: item.path)
                    removed.append(item.path)
                } catch {
                    failed.append("\(item.path) — \(error.localizedDescription)")
                }
            }

            var summary = "已删除 \(removed.count) 项：\n" + removed.map { "  · " + $0 }.joined(separator: "\n")
            if !failed.isEmpty {
                summary += "\n\n未能删除 \(failed.count) 项：\n" + failed.map { "  · " + $0 }.joined(separator: "\n")
            }
            summary += "\n\nApp 本体将在退出后自动移除。"

            step("移除 App 本体…")
            scheduleSelfDelete()

            DispatchQueue.main.async { done(summary) }
        }
    }

    /// 起一个延迟脚本，等 App 退出后再删自身
    private static func scheduleSelfDelete() {
        let bundle = Bundle.main.bundlePath
        guard !bundle.hasPrefix("/private/var/folders") else {
            NSLog("corp-proxy: running translocated at %@, skip self delete", bundle)
            return
        }
        guard bundle.hasSuffix(".app") else { return }
        let script = "sleep 2; /bin/rm -rf \(quote(bundle))"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static var isTranslocated: Bool { Bundle.main.bundlePath.hasPrefix("/private/var/folders") }
}
