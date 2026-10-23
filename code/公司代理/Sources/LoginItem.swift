import Foundation
import ServiceManagement

/// 开机自启：优先用 SMAppService（系统托管，卸载时一并注销）；
/// 若 ad-hoc 签名导致注册失败，则退回自建 LaunchAgent（卸载时同样会被删除）。
enum LoginItem {
    static var launchAgentPath: String {
        NSString(string: "~/Library/LaunchAgents/local.xbguan.corpproxy.plist").expandingTildeInPath
    }

    static var legacyAgentPath: String {
        NSString(string: "~/Library/LaunchAgents/local.xbguan.corpproxy.relay.plist").expandingTildeInPath
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            let s = SMAppService.mainApp.status
            if s == .enabled || s == .requiresApproval { return true }
        }
        return FileManager.default.fileExists(atPath: launchAgentPath)
    }

    static var needsApproval: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .requiresApproval }
        return false
    }

    @discardableResult
    static func enable() -> Bool {
        if #available(macOS 13.0, *) {
            let svc = SMAppService.mainApp
            if svc.status == .enabled || svc.status == .requiresApproval { return true }
            do {
                try svc.register()
                return true
            } catch {
                NSLog("corp-proxy: SMAppService register failed - %@", error.localizedDescription)
            }
        }
        return writeLaunchAgent()
    }

    static func disable() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        }
        let uid = getuid()
        _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", launchAgentPath], timeout: 8)
        try? FileManager.default.removeItem(atPath: launchAgentPath)
    }

    private static func writeLaunchAgent() -> Bool {
        let exe = Bundle.main.executablePath ?? "/Applications/公司代理.app/Contents/MacOS/CorpProxyBar"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>local.xbguan.corpproxy</string>
            <key>ProgramArguments</key>
            <array><string>\(exe)</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><false/>
            <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>
        """
        do {
            let dir = (launchAgentPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
            _ = Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", launchAgentPath], timeout: 8)
            return true
        } catch {
            NSLog("corp-proxy: write LaunchAgent failed - %@", error.localizedDescription)
            return false
        }
    }
}
