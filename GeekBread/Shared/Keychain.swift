import Foundation
import Security

// Tiny Keychain wrapper used by the Cloud AI plumbing to store the user's
// Anthropic API key. Generic-password class, app-scoped — the key never
// leaves the device and never lands in plist/UserDefaults/iCloud.
//
// `kSecAttrSynchronizable = false` keeps it off iCloud Keychain on
// purpose: a paid API key is a per-device secret, not a cross-device
// preference. If a user installs GeekBread on a second iPad they re-enter
// it (or paste from their password manager), same as a TestFlight build.
//
// Errors are flattened to `nil` returns / `false` writes. The Settings UI
// surfaces "couldn't save" once the user taps Save and the read-back fails.

enum Keychain {

    /// Read the string at `account`. Returns nil when the item is missing
    /// or when the stored data isn't valid UTF-8.
    static func readString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      account,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Write `value` at `account`, replacing any existing entry. Returns
    /// true on success. Passing an empty string deletes the entry — the
    /// Settings "Remove key" CTA uses this shape.
    @discardableResult
    static func writeString(_ value: String, account: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return delete(account: account) }
        guard let data = trimmed.data(using: .utf8) else { return false }

        // Try update first; fall back to add when no entry exists.
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      account,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]
        let update: [String: Any] = [
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      account,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
