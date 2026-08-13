//
//  PurchaseTracker+Testing.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import StoreKit

// Test seams for deterministic verification of the dedup / mark-on-send / recovery
// logic without StoreKit. Compiled out of release builds.
//
// These used to live inside PurchaseTracker.swift so they could reach members declared
// `private`. That file has since grown past the 500-line limit CI enforces, so the seams
// moved here and the handful of members they touch — `eventQueue`, `markTransactionIfNew`,
// `markSent`, `sendEnqueuedEvents`, `recordStoreKit1Transaction` — are `internal` rather
// than `private`. `PurchaseTracker` itself is internal, so that widens their reach to
// other files in this module only; nothing is exposed to apps embedding the SDK.

#if DEBUG
    /// Test seams for deterministic verification of the dedup / mark-on-send / recovery logic
    /// without StoreKit. Compiled out of release builds. Lives in the same file so it can reach
    /// the private dedup and send internals.
    @available(iOS 15.0, macOS 12.0, *)
    extension PurchaseTracker {
        /// Enqueues a synthetic purchase through the real dedup + queue path (no StoreKit).
        /// Returns `true` if newly enqueued (not already sent or pending this session).
        func enqueueForTesting(transactionId: String, productId: String = "test.product") -> Bool {
            guard markTransactionIfNew(transactionId) else { return false }
            let event = PurchaseEvent(
                type: "purchase",
                transactionId: transactionId,
                originalTransactionId: nil,
                productId: productId,
                purchaseDate: Date(timeIntervalSince1970: 0),
                price: nil,
                currency: nil,
                countryCode: nil,
                quantity: 1,
                environment: "sandbox"
            )
            eventQueue.enqueue([event])
            return true
        }

        /// Runs the send loop and awaits completion (a real network attempt).
        func flushForTesting() async {
            await sendEnqueuedEvents()
        }

        /// Marks ids as confirmed-sent, simulating a successful network send.
        func markSentForTesting(_ transactionIds: [String]) {
            markSent(transactionIds)
        }

        /// Runs the real StoreKit 1 recording path with a synthetic transaction.
        ///
        /// Covers the plumbing from `recordStoreKit1Transaction` into the queued
        /// `PurchaseEvent`. The `original?.transactionIdentifier ?? transactionId`
        /// fallback itself lives in `paymentQueue(_:updatedTransactions:)` and stays
        /// uncovered: `SKPaymentTransaction` has no public initialiser, so a real
        /// transaction cannot be built in a unit test.
        func recordStoreKit1ForTesting(transactionId: String, originalTransactionId: String?) {
            recordStoreKit1Transaction(
                transactionId: transactionId,
                originalTransactionId: originalTransactionId,
                productId: "test.product",
                quantity: 1,
                date: Date(timeIntervalSince1970: 0)
            )
        }

        /// The events currently queued, for asserting payload contents.
        var queuedEventsForTesting: [PurchaseEvent] {
            eventQueue.peek()
        }

        /// Current depth of the persistent event queue.
        var pendingCountForTesting: Int {
            eventQueue.pendingCount
        }
    }
#endif
