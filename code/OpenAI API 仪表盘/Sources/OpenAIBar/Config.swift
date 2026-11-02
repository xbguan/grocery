import Foundation

enum AppearanceMode: String, Codable, CaseIterable {
    case system, dark, light
}

/// 本地配置。只保存非敏感设置；API Key 单独加密保存（见 KeyStore）。
/// 文件：~/Library/Application Support/OpenAIBar/config.json（权限 600）
struct AppConfig: Codable {
    var appearanceMode: AppearanceMode = .system
    var projectID: String = ""
    var refreshMinutes: Int = 5
    var accountLabel: String = ""

    /// 是否启用「实时余额」：用平台登录态读取，需用户显式打开
    var showCredit: Bool = false

    /// 是否成功读到过余额。用来区分「从未登录」和「登录已失效」两种界面，
    /// 两者的动作相同（重新登录），但文案不能一样，否则用户不知道自己是哪种情况。
    var hasConnectedCredit: Bool = false

    /// 仅存在于内存，永远不会被写入磁盘
    var adminKey: String = ""
    var credentialReadFailed = false

    /// 旧版本遗留在 JSON 里的明文 key，只用于一次性迁移到加密文件
    fileprivate var legacyPlaintextKey: String?

    enum CodingKeys: String, CodingKey {
        case appearanceMode
        case projectID
        case refreshMinutes
        case accountLabel
        case showCredit
        case hasConnectedCredit
        case legacyPlaintextKey = "adminKey"
    }

    init() {}

    /// 手写解码：老版本 config.json 缺少 showCredit 等新字段时不能整份丢弃
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearanceMode = (try? c.decode(AppearanceMode.self, forKey: .appearanceMode)) ?? .system
        projectID = try c.decodeIfPresent(String.self, forKey: .projectID) ?? ""
        refreshMinutes = max(try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? 5, 5)
        accountLabel = try c.decodeIfPresent(String.self, forKey: .accountLabel) ?? ""
        showCredit = try c.decodeIfPresent(Bool.self, forKey: .showCredit) ?? false
        hasConnectedCredit = try c.decodeIfPresent(Bool.self, forKey: .hasConnectedCredit) ?? false
        legacyPlaintextKey = try c.decodeIfPresent(String.self, forKey: .legacyPlaintextKey)
    }

    var trimmedKey: String {
        adminKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasKey: Bool { !trimmedKey.isEmpty }
}

struct ConfigStore {
    static let user = ConfigStore(base: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    let base: URL
    var directory: URL { base.appendingPathComponent("OpenAIApiDashboard", isDirectory: true) }
    var credentials: KeyStore { KeyStore(directory: directory.appendingPathComponent("Credentials")) }
    var fileURL: URL { directory.appendingPathComponent("config.json") }
    private var legacyFileURL: URL { base.appendingPathComponent("OpenAIBar/config.json") }

    func load() -> AppConfig {
        var cfg: AppConfig
        let sourceURL = FileManager.default.fileExists(atPath: fileURL.path)
            ? fileURL
            : (FileManager.default.fileExists(atPath: legacyFileURL.path) ? legacyFileURL : nil)

        if let url = sourceURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            cfg = decoded
        } else {
            cfg = AppConfig()
        }

        do {
            if let stored = try credentials.load() {
                cfg.adminKey = stored
            } else if let legacy = cfg.legacyPlaintextKey, !legacy.isEmpty {
                guard credentials.save(legacy) else {
                    cfg.credentialReadFailed = true
                    return cfg
                }
                cfg.adminKey = legacy
            }
            if cfg.legacyPlaintextKey != nil {
                cfg.legacyPlaintextKey = nil
                save(cfg)
            }
        } catch {
            cfg.credentialReadFailed = true
        }

        // 从旧目录搬过来后重写一次，之后就用新路径
        if sourceURL == legacyFileURL, !cfg.credentialReadFailed, save(cfg) {
            try? FileManager.default.removeItem(at: legacyFileURL)
        }
        return cfg
    }

    @discardableResult
    func save(_ config: AppConfig) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // 双保险：任何情况下都不把 key 写进文件
            var clean = config
            clean.legacyPlaintextKey = nil
            clean.adminKey = ""
            let data = try JSONEncoder().encode(clean)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            NSLog("OpenAIBar: failed to save config: \(error)")
            return false
        }
    }
}
