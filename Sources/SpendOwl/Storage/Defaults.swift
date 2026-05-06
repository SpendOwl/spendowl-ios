//
//  Defaults.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation

/// Internal UserDefaults wrapper for non-sensitive SDK data.
///
/// Stores SDK state like attribution status and sent transaction IDs.
/// Uses a dedicated suite to avoid conflicts with the host app.
final class Defaults: @unchecked Sendable {
    // MARK: - Singleton

    static let shared = Defaults()

    // MARK: - Properties

    private let suite: UserDefaults
    private let prefix = "com.spendowl.sdk."

    // MARK: - Initialization

    private init() {
        suite = UserDefaults(suiteName: "com.spendowl.sdk") ?? .standard
    }

    // MARK: - Keys

    enum Key: String, CaseIterable {
        case attributionSent
        case attributionStatus
        case cachedAttributionResult
        case lastSyncDate
        case sentTransactionIds
        case pendingEvents
        case pendingAttribution
    }

    // MARK: - Accessors

    /// Whether attribution has been sent for this install.
    var attributionSent: Bool {
        get { suite.bool(forKey: prefixed(.attributionSent)) }
        set { suite.set(newValue, forKey: prefixed(.attributionSent)) }
    }

    /// The cached attribution status ("attributed", "organic", or "unknown").
    var attributionStatus: String? {
        get { suite.string(forKey: prefixed(.attributionStatus)) }
        set { suite.set(newValue, forKey: prefixed(.attributionStatus)) }
    }

    /// The date of the last sync with the backend.
    var lastSyncDate: Date? {
        get { suite.object(forKey: prefixed(.lastSyncDate)) as? Date }
        set { suite.set(newValue, forKey: prefixed(.lastSyncDate)) }
    }

    /// The full cached attribution result as JSON data.
    var cachedAttributionResult: Data? {
        get { suite.data(forKey: prefixed(.cachedAttributionResult)) }
        set { suite.set(newValue, forKey: prefixed(.cachedAttributionResult)) }
    }

    /// Transaction IDs that have been sent to prevent duplicates.
    var sentTransactionIds: Set<String> {
        get {
            let array = suite.stringArray(forKey: prefixed(.sentTransactionIds)) ?? []
            return Set(array)
        }
        set {
            suite.set(Array(newValue), forKey: prefixed(.sentTransactionIds))
        }
    }

    /// Pending purchase events as JSON data for retry.
    var pendingEventsData: Data? {
        get { suite.data(forKey: prefixed(.pendingEvents)) }
        set { suite.set(newValue, forKey: prefixed(.pendingEvents)) }
    }

    /// A pending attribution payload as JSON data for cross-launch retry.
    ///
    /// Persisted when the in-memory token-fetch and API retries are exhausted
    /// (or pre-emptively before the first send) so the install isn't lost when
    /// the app is backgrounded or killed mid-flight on first launch.
    var pendingAttributionData: Data? {
        get { suite.data(forKey: prefixed(.pendingAttribution)) }
        set { suite.set(newValue, forKey: prefixed(.pendingAttribution)) }
    }

    // MARK: - Helpers

    private func prefixed(_ key: Key) -> String {
        prefix + key.rawValue
    }

    /// Resets all stored values.
    ///
    /// Used primarily for testing.
    func reset() {
        for key in Key.allCases {
            suite.removeObject(forKey: prefixed(key))
        }
    }
}
