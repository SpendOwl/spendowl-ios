//
//  AttributionQueue.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation

/// A persisted attribution payload waiting to be sent to the backend.
///
/// Captures everything needed to rebuild an `AttributionRequest` on a future
/// launch, so the install isn't lost if the app is backgrounded or killed
/// before the in-flight network request completes.
struct PendingAttribution: Codable, Equatable {
    let attributionToken: String
    let bundleId: String
    let appVersion: String
    let sdkVersion: String
    let userId: String?
    let osVersion: String
    let deviceModel: String
    let locale: String
    let createdAt: Date
}

/// Internal single-slot persistent queue for attribution payloads.
///
/// Mirrors the pattern in ``EventQueue`` but holds at most one pending record
/// — the install is a single event by definition. The slot is written when a
/// send is about to be attempted (so we survive app suspension mid-request)
/// and cleared after the backend acknowledges the payload.
///
/// Storage is `UserDefaults`, which is plaintext and readable on a jailbroken
/// device. The pending payload is cleared on the next successful send so the
/// attribution token is never persisted long-term — Apple advises against
/// long-term storage of attribution tokens. If a launch never reaches a
/// successful send, a stale token will linger until the next launch's replay.
@available(iOS 15.0, macOS 12.0, *)
final class AttributionQueue: @unchecked Sendable {
    // MARK: - Properties

    private let defaults: Defaults
    private let lock = NSLock()

    // MARK: - Initialization

    init(defaults: Defaults = .shared) {
        self.defaults = defaults
    }

    // MARK: - Queue Operations

    /// Persists the pending attribution payload, overwriting any previous one.
    func save(_ pending: PendingAttribution) {
        lock.lock()
        defer { lock.unlock() }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            defaults.pendingAttributionData = try encoder.encode(pending)
            Logger.log("Pending attribution persisted to disk", level: .debug)
        } catch {
            Logger.log("Failed to encode pending attribution: \(error)", level: .error)
        }
    }

    /// Returns the persisted attribution payload, if any.
    func load() -> PendingAttribution? {
        lock.lock()
        defer { lock.unlock() }

        guard let data = defaults.pendingAttributionData else { return nil }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PendingAttribution.self, from: data)
        } catch {
            Logger.log("Failed to decode pending attribution, dropping: \(error)", level: .error)
            defaults.pendingAttributionData = nil
            return nil
        }
    }

    /// Removes the pending attribution payload after a successful send.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.pendingAttributionData = nil
    }

    /// Whether a pending attribution is currently persisted.
    var hasPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return defaults.pendingAttributionData != nil
    }
}
