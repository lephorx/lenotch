import Foundation
import Security

/// Lenotch's secrets (API keys, the DeepSeek session) in the login keychain.
///
/// Items are written and read through `/usr/bin/security` rather than the Security framework.
/// Lenotch is signed with a self-signed certificate (no Apple team ID), so items it creates
/// itself are locked to the exact build (`cdhash:` in the item's partition list): every update
/// is a new build, and macOS asked for the login password again. Items made by `security`
/// trust that tool (`apple-tool:`), which stays the same across Lenotch updates.
/// They're kept under `<service>.v2`, so `security` never touches an old item (that would prompt).
enum Keychain {
    private static let tool = "/usr/bin/security"
    private static let lock = NSLock()
    private static var cache: [String: String?] = [:]

    static func value(service: String, account: String) -> String? {
        let cacheKey = service + "\n" + account
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[cacheKey] { return cached }
        let value = run(["find-generic-password", "-s", service + ".v2", "-a", account, "-w"])
            .map(decodePrinted).flatMap { $0.isEmpty ? nil : $0 } ?? migrateLegacy(service: service, account: account)
        cache[cacheKey] = .some(value)
        return value
    }

    /// Saves the value; an empty one removes it.
    static func set(_ value: String, service: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        deleteLegacy(service: service, account: account)
        write(trimmed, service: service, account: account)
        cache[service + "\n" + account] = .some(trimmed.isEmpty ? nil : trimmed)
    }

    private static func write(_ value: String, service: String, account: String) {
        let service = service + ".v2"
        guard !value.isEmpty else {
            _ = run(["delete-generic-password", "-s", service, "-a", account])
            return
        }
        // Commands go through stdin and the value as hex, so the secret never shows up
        // in the process list and needs no quoting.
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        _ = run(["-i"], input: "add-generic-password -U -s \(service) -a \(account) -X \(hex)\n")
    }

    /// Moves an item saved by Lenotch 2.13 or older (through the Security framework) over to
    /// `security`. Reading it may ask for the password one last time.
    /// `security -w` prints values with anything but printable ASCII as hex. A value that is
    /// printable ASCII is printed as is, so hex only counts when it decodes to something else.
    private static func decodePrinted(_ text: String) -> String {
        guard text.count.isMultiple(of: 2), text.allSatisfy(\.isHexDigit) else { return text }
        var bytes = [UInt8]()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return text }
            bytes.append(byte)
            index = next
        }
        guard bytes.contains(where: { $0 < 0x20 || $0 > 0x7E }),
              let decoded = String(bytes: bytes, encoding: .utf8) else { return text }
        return decoded
    }

    private static func migrateLegacy(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        write(value, service: service, account: account)
        deleteLegacy(service: service, account: account)
        return value
    }

    private static func deleteLegacy(service: String, account: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
    }

    @discardableResult
    private static func run(_ arguments: [String], input: String? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        let stdin = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        do { try process.run() } catch { return nil }
        if let input {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
