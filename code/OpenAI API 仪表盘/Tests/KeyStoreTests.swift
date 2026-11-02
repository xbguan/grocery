import Foundation
import Security

@main
enum KeyStoreTests {
    static func main() {
        var reads: [(String, String)] = []
        let key = KeyStore.load { service, account in
            reads.append((service, account))
            return nil
        }
        precondition(key == nil)
        precondition(reads.count == 1)
        precondition(reads[0].0 == "com.xbguan.openai-api-dashboard")
        precondition(reads[0].1 == "openai-admin-key-v3")

        let query = KeyStore.baseQuery("com.xbguan.openai-api-dashboard")
        precondition(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String)
        print("KeyStoreTests passed")
    }
}
