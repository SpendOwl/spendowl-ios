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

    /// A transaction still in the persisted queue from a prior launch must not be
    /// re-enqueued as a duplicate by the next launch's recovery scan.
    func testPersistedQueuedTransactionIsNotDuplicatedNextLaunch() async {
        let first = makeTracker()
        XCTAssertTrue(first.enqueueForTesting(transactionId: "tx-queued"))
        await first.flushForTesting() // fails: tx-queued stays in the persisted queue, unsent
        XCTAssertEqual(first.pendingCountForTesting, 1)
        XCTAssertFalse(Defaults.shared.sentTransactionIds.contains("tx-queued"))

        // Next launch: a fresh tracker seeds its pending set from the persisted queue, so the
        // same id is recognised as already queued and is not enqueued a second time.
        let next = makeTracker()
        XCTAssertFalse(
            next.enqueueForTesting(transactionId: "tx-queued"),
            "a transaction already in the persisted queue must not be enqueued twice"
        )
        XCTAssertEqual(next.pendingCountForTesting, 1, "the queue must still hold exactly one copy")
    }

    // MARK: - StoreKit 1 path

    /// SK1-recorded events used to ship `originalTransactionId: nil`, which kept them out
    /// of the backend's lineage matching on `apple_webhooks.original_transaction_id`.
    func testStoreKit1EventCarriesOriginalTransactionId() {
        let tracker = makeTracker()

        tracker.recordStoreKit1ForTesting(transactionId: "tx-renewal", originalTransactionId: "tx-original")

        let event = tracker.queuedEventsForTesting.first
        XCTAssertEqual(event?.transactionId, "tx-renewal")
        XCTAssertEqual(event?.originalTransactionId, "tx-original", "SK1 events must carry the original id")
    }

    /// For an initial purchase StoreKit 1 leaves `original` nil, and `paymentQueue` falls
    /// back to the transaction's own id so the payload matches StoreKit 2's `originalID`.
    func testStoreKit1InitialPurchaseReportsSelfAsOriginal() {
        let tracker = makeTracker()

        tracker.recordStoreKit1ForTesting(transactionId: "tx-first", originalTransactionId: "tx-first")

        let event = tracker.queuedEventsForTesting.first
        XCTAssertEqual(event?.originalTransactionId, "tx-first")
    }

    // MARK: - Restart

    /// `stopObserving` re-seeds the pending set from the queue: an id that was claimed but
    /// then evicted must become re-enqueueable, while an id still queued stays deduped.
    func testStopObservingReleasesEvictedIdsButKeepsQueuedOnes() {
        let tracker = makeTracker()
        XCTAssertTrue(tracker.enqueueForTesting(transactionId: "tx-kept"))
        XCTAssertTrue(tracker.enqueueForTesting(transactionId: "tx-evicted"))

        // Simulate the bounded queue evicting one of them before any send succeeded.
        Defaults.shared.pendingEventsData = nil
        XCTAssertTrue(tracker.enqueueForTesting(transactionId: "tx-kept-requeue"))
        XCTAssertEqual(tracker.queuedEventsForTesting.map(\.transactionId), ["tx-kept-requeue"])

        tracker.stopObserving()

        XCTAssertTrue(
            tracker.enqueueForTesting(transactionId: "tx-evicted"),
            "an id claimed but no longer queued must be released on stop"
        )
        XCTAssertFalse(
            tracker.enqueueForTesting(transactionId: "tx-kept-requeue"),
            "an id still in the queue must stay deduped after stop"
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
