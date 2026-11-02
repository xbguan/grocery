import Foundation
import Security

// Run once as "seed", then from a replacement executable as "upgrade".
// All operations target a disposable keychain and dummy credentials.
@main
enum KeyStoreTests {
    static func main() throws {
        let args = CommandLine.arguments
        precondition(args.count == 3 && ["seed", "upgrade"].contains(args[1]))
        let path = args[2]
        precondition(path.hasPrefix("/private/tmp/") && path.hasSuffix("/fixture.keychain"))
        var fixture: SecKeychain?
        if args[1] == "seed" {
            precondition(!FileManager.default.fileExists(atPath: path))
            let password = UUID().uuidString
            precondition(SecKeychainCreate(path, UInt32(password.utf8.count), password, false, nil, &fixture) == errSecSuccess)
        } else {
            precondition(SecKeychainOpen(path, &fixture) == errSecSuccess)
        }
        guard let fixture else { fatalError("Missing fixture") }
        let store = KeyStore(service: "grocery.tests.key-store", keychain: fixture)
        if args[1] == "seed" {
            precondition(store.load() == nil)
            precondition(store.save("fixture-one"))
            precondition(store.load() == "fixture-one")
            print("Fresh save/read passed")
            return
        }
        defer { SecKeychainDelete(fixture) }
        let carried = store.load()
        var allowed: DarwinBoolean = true
        precondition(SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess && !allowed.boolValue)
        precondition(carried == nil || carried == "fixture-one")
        print(carried == nil ? "Upgrade: denied silently" : "Upgrade: previous key read silently")
        precondition(store.save("fixture-two"))
        precondition(store.load() == "fixture-two")
        precondition(store.delete() && store.load() == nil)
        // Create an item whose decrypt ACL trusts only the fixture writer.
        let writer = Process()
        writer.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        writer.arguments = ["add-generic-password", "-s", "grocery.tests.denied",
                            "-a", "openai-admin-key-v3", "-w", "fake-denied",
                            "-T", "/usr/bin/security", path]
        try writer.run()
        writer.waitUntilExit()
        precondition(writer.terminationStatus == 0)
        let restricted = KeyStore(service: "grocery.tests.denied", keychain: fixture)
        precondition(restricted.load() == nil)
        print("Untrusted-app ACL denied silently")
        precondition(store.save("fixture-lock"))
        precondition(SecKeychainLock(fixture) == errSecSuccess)
        precondition(store.load() == nil)
        print("Replacement, delete and locked-keychain denial passed")
    }
}
