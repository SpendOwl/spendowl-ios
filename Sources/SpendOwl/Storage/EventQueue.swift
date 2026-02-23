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

    /// Removes the first `count` events from the queue after successful send.
    ///
    /// - Parameter count: The number of events to remove from the front.
    func remove(count: Int) {
        guard count > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        var current = loadEvents()
        let removeCount = min(count, current.count)
        current.removeFirst(removeCount)
        saveEvents(current)

        Logger.log("Removed \(removeCount) events from queue, remaining: \(current.count)", level: .debug)
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
