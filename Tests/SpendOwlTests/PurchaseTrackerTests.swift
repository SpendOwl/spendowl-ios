//
//  PurchaseTrackerTests.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

@testable import SpendOwl
import XCTest

/// Deterministic verification of the consumable-recovery dedup logic.
///
/// These tests do not exercise `Transaction.all` itself (a system API that returns nothing
/// in a unit-test host); they lock the dedup / mark-on-send / recovery invariants that the
/// recovery scan depends on, via the in-file test seams on `PurchaseTracker`.
///
/// The network is pointed at an unroutable loopback port so every send fails fast (connection
/// refused, no retry/backoff with `maxRetries: 1`) — the same approach `AttributionTests` uses.
@available(iOS 15.0, macOS 12.0, *)
final class PurchaseTrackerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Defaults.shared.reset()
    }

    override func tearDown() {
        Defaults.shared.reset()
        super.tearDown()
    }

    // MARK: - Dedup

    func testEnqueueDedupWithinSession() {
        let tracker = makeTracker()
        XCTAssertTrue(tracker.enqueueForTesting(transactionId: "tx-1"))
        XCTAssertFalse(tracker.enqueueForTesting(transactionId: "tx-1"), "same id must not enqueue twice in a session")
    }

    func testConfirmedSentIdIsDedupedAcrossTrackers() {
        let tracker = makeTracker()
        XCTAssertTrue(tracker.enqueueForTesting(transactionId: "tx-ok"))

        // Simulate a successful network send.
        tracker.markSentForTesting(["tx-ok"])
        XCTAssertTrue(Defaults.shared.sentTransactionIds.contains("tx-ok"), "successful send must persist the id")

        // A fresh tracker (next launch) must treat the confirmed-sent id as already handled.
        let next = makeTracker()
        XCTAssertFalse(next.enqueueForTesting(transactionId: "tx-ok"), "confirmed-sent id must stay deduped")
    }

    // MARK: - Mark-on-send (the recovery-loss fix)

    /// A failed send must NOT persist the transaction id. The pre-fix code marked at enqueue
    /// time, so a failed/evicted event was lost forever.
    func testFailedSendDoesNotPersistId() async {
        let tracker = makeTracker()
        XCTAssertTrue(tracker.enqueueForTesting(transactionId: "tx-miss"))

        await tracker.flushForTesting() // send fails (unroutable host)

        XCTAssertFalse(
            Defaults.shared.sentTransactionIds.contains("tx-miss"),
            "an unsent transaction must not be recorded as sent"
        )
        XCTAssertEqual(tracker.pendingCountForTesting, 1, "the event must stay queued for retry")
    }

    /// An event dropped from the bounded queue before it was sent must be recoverable on the
    /// next launch, because its id was never persisted as sent.
    func testEvictedBeforeSendIsRecoverableNextLaunch() async {
        let first = makeTracker()
        XCTAssertTrue(first.enqueueForTesting(transactionId: "tx-drop"))
        await first.flushForTesting() // fails: tx-drop is queued but not persisted
        XCTAssertFalse(Defaults.shared.sentTransactionIds.contains("tx-drop"))

        // Simulate the bounded EventQueue dropping the event (overflow / eviction) without
        // touching the confirmed-sent store.
        Defaults.shared.pendingEventsData = nil

        // Next launch: a fresh tracker has an empty in-memory pending set, and the persistent
        // store never recorded tx-drop — so the recovery scan can re-enqueue it.
        let next = makeTracker()
        XCTAssertTrue(
            next.enqueueForTesting(transactionId: "tx-drop"),
            "a dropped, never-sent transaction must be re-enqueueable on the next launch"
        )
    }

    // MARK: - Helpers

    private func makeTracker() -> PurchaseTracker {
        let configuration = SpendOwlConfiguration(
            apiKey: "test",
            // swiftlint:disable:next force_unwrapping
            baseURL: URL(string: "http://127.0.0.1:1/api")!,
            timeoutInterval: 1,
            maxRetries: 1
        )
        return PurchaseTracker(apiClient: APIClient(configuration: configuration))
    }
}
