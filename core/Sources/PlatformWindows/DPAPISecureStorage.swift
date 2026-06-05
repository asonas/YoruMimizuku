#if canImport(WinSDK)
import Foundation
import WinSDK
import BlueskyCore

/// Windows `SecureStorage` backed by DPAPI (`CryptProtectData` /
/// `CryptUnprotectData`) with per-user protection, persisting each value as an
/// encrypted file under the app's Application Support directory.
///
/// DPAPI (rather than the Credential Manager) is used because the stored account
/// blob bundles OAuth tokens (JWTs) plus the DPoP key and can exceed the
/// Credential Manager's per-item blob size limit. DPAPI ties decryption to the
/// current Windows user account, which is the closest equivalent to the Keychain
/// guarantee on macOS.
public struct DPAPISecureStorage: SecureStorage {
    private let directory: URL

    /// `service` namespaces all items (use the app id, e.g. "as.ason.YoruMimizuku").
    public init(service: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = base
            .appendingPathComponent(service, isDirectory: true)
            .appendingPathComponent("secure", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // Hex-encode the key so arbitrary characters (DIDs contain ':') map to a
    // valid, collision-free Windows file name.
    private func fileURL(_ key: String) -> URL {
        let safe = Data(key.utf8).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(safe).appendingPathExtension("bin")
    }

    public func set(_ data: Data, for key: String) throws {
        let encrypted = try DPAPI.protect(data)
        try encrypted.write(to: fileURL(key), options: .atomic)
    }

    public func data(for key: String) throws -> Data? {
        let url = fileURL(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let encrypted = try Data(contentsOf: url)
        return try DPAPI.unprotect(encrypted)
    }

    public func remove(for key: String) throws {
        let url = fileURL(key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// Errors from the DPAPI-backed secure storage.
public enum DPAPIError: Error, Equatable {
    case protectFailed
    case unprotectFailed
}

enum DPAPI {
    // CRYPTPROTECT_UI_FORBIDDEN: never show UI (we run headless).
    private static let uiForbidden: DWORD = 0x1

    static func protect(_ data: Data) throws -> Data {
        try transform(data, encrypt: true)
    }

    static func unprotect(_ data: Data) throws -> Data {
        try transform(data, encrypt: false)
    }

    private static func transform(_ data: Data, encrypt: Bool) throws -> Data {
        var output = DATA_BLOB()
        var mutable = [UInt8](data)
        mutable.withUnsafeMutableBufferPointer { ptr in
            var input = DATA_BLOB(cbData: DWORD(ptr.count), pbData: ptr.baseAddress)
            if encrypt {
                _ = CryptProtectData(&input, nil, nil, nil, nil, uiForbidden, &output)
            } else {
                _ = CryptUnprotectData(&input, nil, nil, nil, nil, uiForbidden, &output)
            }
        }
        // Success is signalled by a non-null output buffer; this avoids depending on
        // how the Win32 BOOL return is bridged into Swift.
        guard let bytes = output.pbData else {
            throw encrypt ? DPAPIError.protectFailed : DPAPIError.unprotectFailed
        }
        defer { LocalFree(output.pbData) }
        return Data(bytes: bytes, count: Int(output.cbData))
    }
}
#endif
