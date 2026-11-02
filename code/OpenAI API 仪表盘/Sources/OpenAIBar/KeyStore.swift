import CryptoKit
import Foundation

/// Version 1: a format byte followed by CryptoKit's combined nonce, ciphertext and tag.
/// The random local encryption key lives outside the versioned app bundle.
struct KeyStore {
    let directory: URL
    private var secretURL: URL { directory.appendingPathComponent("admin.enc") }
    private var keyURL: URL { directory.appendingPathComponent("local.key") }

    private func readKey() throws -> SymmetricKey {
        let data = try Data(contentsOf: keyURL)
        guard data.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
        return SymmetricKey(data: data)
    }

    func load() throws -> String? {
        let file: Data
        do { file = try Data(contentsOf: secretURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        guard file.first == 1 else { throw CocoaError(.fileReadCorruptFile) }
        let box = try AES.GCM.SealedBox(combined: file.dropFirst())
        let data = try AES.GCM.open(box, using: readKey())
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }

    /// Publish only finished, owner-readable files. Concurrent first saves must
    /// converge on one local key, never replace another process's key.
    private func publish(_ data: Data, to url: URL, replace: Bool) throws {
        var template = Array(directory.appendingPathComponent(".write.XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let temporary = String(cString: template)
        defer { unlink(temporary) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        let result = replace ? rename(temporary, url.path) : link(temporary, url.path)
        if result != 0 && (replace || errno != EEXIST) {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func save(_ value: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let key: SymmetricKey
            do { key = try readKey() }
            catch let e as CocoaError where e.code == .fileReadNoSuchFile {
                let bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                try publish(bytes, to: keyURL, replace: false)
                key = try readKey()
            }
            let box = try AES.GCM.seal(Data(value.utf8), using: key)
            guard let combined = box.combined else { return false }
            try publish(Data([1]) + combined, to: secretURL, replace: true)
            return true
        } catch { return false }
    }

    func delete() -> Bool {
        unlink(secretURL.path) == 0 || errno == ENOENT
    }
}
