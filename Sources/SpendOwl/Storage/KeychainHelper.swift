//
//  KeychainHelper.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import Security

/// Internal helper for secure storage using iOS Keychain.
///
/// Stores sensitive data like API keys with hardware-backed encryption.
/// Data is protected with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// for security while allowing background access.
final class KeychainHelper: @unchecked Sendable {
    // MARK: - Singleton

    static let shared = KeychainHelper()

    // MARK: - Properties

    private let service = "com.spendowl.sdk"

    // MARK: - Keys

    private enum Keys {
        static let anonymousId = "anonymous_id"
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Anonymous ID

    /// Returns a persistent anonymous device identifier.
    ///
    /// This ID is generated once and stored in the Keychain, persisting across
    /// app reinstalls (if Keychain is not cleared). Used when the app developer
    /// doesn't set a custom user ID.
    ///
    /// - Returns: A stable UUID string for this device.
    func getOrCreateAnonymousId() -> String {
        if let existingId = get(Keys.anonymousId) {
            return existingId
        }

        let newId = "$SpendOwlID:\(UUID().uuidString.lowercased())"
        if !set(newId, forKey: Keys.anonymousId) {
            Logger.log("Failed to persist anonymous ID to Keychain", level: .error)
        }
        return newId
    }

    // MARK: - Public Methods

    /// Stores a string value securely in the Keychain.
    ///
    /// - Parameters:
    ///   - value: The string to store.
    ///   - key: The key to store it under.
    /// - Returns: `true` if the value was stored successfully.
    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        // Delete existing item first
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess, deleteStatus != errSecItemNotFound {
            Logger.log("Keychain delete failed for '\(key)': OSStatus \(deleteStatus)", level: .error)
        }

        // Add new item with secure accessibility
        var newQuery = query
        newQuery[kSecValueData as String] = data
        newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            Logger.log("Keychain add failed for '\(key)': OSStatus \(addStatus)", level: .error)
            return false
        }

        return true
    }

    /// Retrieves a string value from the Keychain.
    ///
    /// - Parameter key: The key to retrieve.
    /// - Returns: The stored string, or `nil` if not found.
    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    /// Deletes a value from the Keychain.
    ///
    /// - Parameter key: The key to delete.
    /// - Returns: `true` if the item was deleted or did not exist.
    @discardableResult
    func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            Logger.log("Keychain delete failed for '\(key)': OSStatus \(status)", level: .error)
            return false
        }

        return true
    }
}
