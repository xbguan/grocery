import Foundation

/// Run seed and upgrade as separate binaries with CREDENTIAL_TEST_HOME set to an empty test home.
@main
enum KeyStoreTests {
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["CREDENTIAL_TEST_HOME"], home.hasPrefix("/private/tmp/grocery-store-") else { fatalError("Isolated test home required") }
        let config = ConfigStore(base: URL(fileURLWithPath: home))
        let store = config.credentials
        let enc = store.directory.appendingPathComponent("admin.enc")
        let local = store.directory.appendingPathComponent("local.key")
        var cfg = config.load()
        switch CommandLine.arguments.last {
        case "seed":
            precondition(!cfg.hasKey && !cfg.credentialReadFailed)
            precondition(store.save("dummy-upgrade-key"))
            cfg.adminKey = "dummy-upgrade-key"
            cfg.accountLabel = "fixture"
            cfg.projectID = "proj-fixture"
            cfg.appearanceMode = .dark
            cfg.refreshMinutes = 15
            config.save(cfg)
            for url in [enc, local, config.fileURL] {
                let data = try Data(contentsOf: url)
                precondition(data.range(of: Data(cfg.adminKey.utf8)) == nil)
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                precondition((attrs[.posixPermissions] as? Int) == 0o600)
            }
        case "upgrade":
            precondition(cfg.adminKey == "dummy-upgrade-key" && !cfg.credentialReadFailed)
            precondition(cfg.projectID == "proj-fixture" && cfg.accountLabel == "fixture")
            precondition(cfg.appearanceMode == .dark && cfg.refreshMinutes == 15)
            precondition(store.save("dummy-replacement"))
            precondition(config.load().adminKey == "dummy-replacement")
            var bytes = try Data(contentsOf: enc)
            bytes[bytes.count - 1] ^= 1
            try bytes.write(to: enc)
            precondition(config.load().credentialReadFailed)
            precondition(store.delete())
            let after = config.load()
            precondition(!after.hasKey && !after.credentialReadFailed && after.accountLabel == "fixture")
        default: fatalError("Expected seed or upgrade")
        }
        print("PASS", CommandLine.arguments.last!)
    }
}
