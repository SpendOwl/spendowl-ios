//
//  EventQueue.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation

/// Internal persistent queue for purchase events that failed to send.
///
/// Stores events as JSON in UserDefaults with a bounded size to prevent
/// unbounded storage growth. Events are retried on the next successful send.
@available(iOS 15.0, macOS 12.0, *)
final class EventQueue: @unchecked Sendable {
    // MARK: - Properties

    private let defaults: Defaults
    private let lock = NSLock()
    private let maxEvents = 100

    // MARK: - Initialization

    init(defaults: Defaults = .shared) {
        self.defaults = defaults
    }

    // MARK: - Queue Operations

    /// Adds events to the persistent queue.
    ///
    /// If the queue exceeds the maximum size, oldest events are dropped.
    ///
    /// - Parameter events: The purchase events to enqueue.
    func enqueue(_ events: [PurchaseEvent]) {
        guard !events.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        var current = loadEvents()
        current.append(contentsOf: events)

        // Trim to max size, keeping newest events
        if current.count > maxEvents {
            let overflow = current.count - maxEvents
            current.removeFirst(overflow)
            Logger.log("Event queue overflow, dropped \(overflow) oldest events", level: .info)
        }

        saveEvents(current)
        Logger.log("Enqueued \(events.count) events, queue size: \(current.count)", level: .debug)
    }

    /// Returns all pending events without removing them.
    ///
    /// - Returns: The pending events in FIFO order.
    func peek() -> [PurchaseEvent] {
        lock.lock()
        defer { lock.unlock() }
        return loadEvents()
    }

    /// Removes the events with the given transaction IDs after a successful send.
    ///
    /// Removal is identity-based, never positional. A send takes a snapshot of the
    /// queue and then awaits the network; events enqueued during that window are
    /// appended, and if the queue overflows they are trimmed from the *front*. So by
    /// the time the send returns, a positional `removeFirst(snapshot.count)` would
    /// discard events the send never carried — permanently, since they are already
    /// marked pending in memory and so cannot be re-enqueued this session, yet were
    /// never marked sent. Matching on IDs removes exactly what was sent and leaves
    /// everything else queued for the next send.
    ///
    /// IDs no longer in the queue (trimmed by overflow while the send was in flight)
    /// are simply ignored.
    ///
    /// - Parameter transactionIds: The transaction IDs confirmed sent.
    func remove(transactionIds: [String]) {
        guard !transactionIds.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        let sent = Set(transactionIds)
        let current = loadEvents()
        let remaining = current.filter { !sent.contains($0.transactionId) }

        guard remaining.count != current.count else { return }
        saveEvents(remaining)

        Logger.log(
            "Removed \(current.count - remaining.count) sent events from queue, remaining: \(remaining.count)",
            level: .debug
        )
    }

    /// The number of events waiting to be sent.
    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadEvents().count
    }

    // MARK: - Persistence

    private func loadEvents() -> [PurchaseEvent] {
        guard let data = defaults.pendingEventsData else { return [] }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([PurchaseEvent].self, from: data)
        } catch {
            Logger.log("Failed to decode pending events: \(error)", level: .error)
            return []
        }
    }

    private func saveEvents(_ events: [PurchaseEvent]) {
        guard !events.isEmpty else {
            defaults.pendingEventsData = nil
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            defaults.pendingEventsData = try encoder.encode(events)
        } catch {
            Logger.log("Failed to encode pending events: \(error)", level: .error)
        }
    }
}
