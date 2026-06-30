//
//  PurchaseTracker.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import StoreKit

/// Internal service for fully automatic purchase tracking.
///
/// Uses three complementary listeners to capture every purchase:
/// 1. `SKPaymentTransactionObserver` — catches the first purchase in the same session
/// 2. `Transaction.updates` — catches renewals, cross-device, Ask to Buy, offer codes
/// 3. `Transaction.all` — startup safety net for missed purchases (incl. consumables,
///    which `currentEntitlements` omits by design)
///
/// Deduplication is atomic and transactionId-based: the persisted `sentTransactionIds`
/// (confirmed sends) combined with an in-memory pending set, so events dropped from the
/// bounded queue before sending are recovered on a later launch rather than lost.
/// The SDK is fully read-only: neither `transaction.finish()` nor `finishTransaction()` is called.
@available(iOS 15.0, macOS 12.0, *)
final class PurchaseTracker: NSObject, SKPaymentTransactionObserver, @unchecked Sendable {
    // MARK: - Properties

    private let apiClient: APIClient
    private let defaults = Defaults.shared
    private let eventQueue: EventQueue
    private let lock = NSLock()
    private var scanTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var _externalUserId: String?
    private var _isSending = false
    /// Transaction IDs enqueued this session but not yet confirmed sent. Combined with the
    /// persisted `sentTransactionIds` (confirmed-sent only) for dedup, so a transaction
    /// evicted from the bounded `EventQueue` before sending is re-enqueued on a future
    /// launch instead of being permanently dropped. Guarded by `lock`.
    private var _pendingTransactionIds: Set<String> = []

    // MARK: - Initialization

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        let queue = EventQueue()
        eventQueue = queue
        // Seed the in-memory pending set from events a prior launch persisted but never sent,
        // so the recovery scan doesn't enqueue duplicates of transactions already queued.
        // Evicted (dropped) events are absent from the queue, so they stay recoverable.
        _pendingTransactionIds = Set(queue.peek().map(\.transactionId))
        super.init()
    }

    // MARK: - Public Methods

    /// Sets the developer-supplied external user ID attached to purchase events
    /// as reporting metadata. Does not affect linkage (always the anonymous ID).
    ///
    /// - Parameter externalUserId: The developer's user identifier, or `nil` to clear.
    func setExternalUserId(_ externalUserId: String?) {
        lock.lock()
        defer { lock.unlock() }
        _externalUserId = externalUserId
    }

    /// Starts fully automatic purchase tracking.
    ///
    /// 1. Registers `SKPaymentTransactionObserver` (sync — immediately active)
    /// 2. Flushes pending events and scans `Transaction.all` (async)
    /// 3. Starts `Transaction.updates` listener (async, long-running)
    func startObserving() {
        lock.lock()
        guard scanTask == nil else {
            lock.unlock()
            return
        }

        // Flush pending events first, then scan entitlements — sequential
        // to avoid concurrent EventQueue access.
        scanTask = Task { [weak self] in
            guard let self else { return }
            await sendEnqueuedEvents()
            await scanAllTransactions()
        }

        // StoreKit 2 listener — catches renewals, cross-device, Ask to Buy, offer codes
        updateTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await processVerificationResult(result)
            }
        }

        lock.unlock()

        // StoreKit 1 observer — MUST be outside the lock because add() can
        // synchronously call paymentQueue(_:updatedTransactions:) with pending
        // transactions, which calls markTransactionIfNew → lock.lock() → deadlock.
        SKPaymentQueue.default().add(self)

        Logger.log("Purchase tracking started (automatic)", level: .debug)
    }

    /// Stops purchase tracking.
    ///
    /// This is typically only called during testing or when the SDK is reset.
    func stopObserving() {
        lock.lock()
        scanTask?.cancel()
        scanTask = nil
        updateTask?.cancel()
        updateTask = nil
        lock.unlock()

        SKPaymentQueue.default().remove(self)

        Logger.log("Stopped purchase tracking", level: .debug)
    }

    // MARK: - SKPaymentTransactionObserver

    /// Called by StoreKit 1 for every transaction state change.
    ///
    /// We only care about `.purchased` — the first purchase in the current session.
    /// `finishTransaction()` is never called (read-only SDK).
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions where transaction.transactionState == .purchased {
            guard let transactionId = transaction.transactionIdentifier else { continue }
            recordStoreKit1Transaction(
                transactionId: transactionId,
                productId: transaction.payment.productIdentifier,
                quantity: transaction.payment.quantity,
                date: transaction.transactionDate ?? Date()
            )
        }
    }

    // MARK: - Transaction Recording

    /// Records a purchase observed via `SKPaymentTransactionObserver`.
    private func recordStoreKit1Transaction(
        transactionId: String,
        productId: String,
        quantity: Int,
        date: Date
    ) {
        guard markTransactionIfNew(transactionId) else { return }

        let event = PurchaseEvent(
            type: "purchase",
            transactionId: transactionId,
            originalTransactionId: nil,
            productId: productId,
            purchaseDate: date,
            price: nil,
            currency: nil,
            countryCode: nil,
            quantity: quantity,
            environment: resolveEnvironmentFromReceipt()
        )

        eventQueue.enqueue([event])

        Task { [weak self] in
            await self?.sendEnqueuedEvents()
        }

        Logger.log("SK1 recorded transaction: \(transactionId)", level: .info)
    }

    /// Processes a StoreKit 2 verification result. Never calls `transaction.finish()` —
    /// the SDK is read-only and does not interfere with the StoreKit lifecycle.
    private func processVerificationResult(_ result: VerificationResult<Transaction>) async {
        switch result {
        case let .verified(transaction):
            await recordTransaction(transaction)

        case let .unverified(_, error):
            Logger.log("Unverified transaction: \(error)", level: .error)
        }
    }

    /// Records a StoreKit 2 transaction and sends immediately.
    ///
    /// SDK only sends the attribution↔transaction link.
    /// Price, currency, product type etc. come from App Store Server
    /// Notifications on the backend — no async enrichment needed.
    private func recordTransaction(_ transaction: Transaction) async {
        guard enqueueTransaction(transaction) else { return }
        await sendEnqueuedEvents()
    }

    /// Enqueues a StoreKit 2 transaction without sending. Returns `true` if new.
    private func enqueueTransaction(_ transaction: Transaction) -> Bool {
        let transactionId = String(transaction.id)
        guard markTransactionIfNew(transactionId) else { return false }

        let event = PurchaseEvent(
            type: "purchase",
            transactionId: transactionId,
            originalTransactionId: String(transaction.originalID),
            productId: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            price: nil,
            currency: nil,
            countryCode: nil,
            quantity: transaction.purchasedQuantity,
            environment: resolveEnvironment(for: transaction)
        )

        eventQueue.enqueue([event])
        Logger.log("Recorded transaction: \(transactionId)", level: .info)
        return true
    }

    // MARK: - Transaction History Scan

    /// Number of new transactions to accumulate before flushing mid-scan. Keeps the
    /// persistent `EventQueue` (capped at 100) from overflowing on large histories.
    private static let scanFlushBatchSize = 50

    /// Scans `Transaction.all` as a safety net for missed purchases.
    ///
    /// Unlike `currentEntitlements`, `Transaction.all` returns the customer's full
    /// transaction history — **including consumables** (which `currentEntitlements`
    /// excludes by design). Refunded/revoked entries are also included but harmless:
    /// the SDK only sends the attribution↔transaction link, never price or revocation
    /// state (those arrive via App Store Server Notifications on the backend).
    ///
    /// New events are batched and flushed every ``scanFlushBatchSize`` transactions so
    /// the bounded `EventQueue` never overflows on long-lived customers; a final flush
    /// drains the remainder. Dedup via `sentTransactionIds` makes re-emitting history on
    /// each launch cheap and the backend is idempotent.
    private func scanAllTransactions() async {
        Logger.log("Scanning transaction history", level: .debug)
        var count = 0
        for await result in Transaction.all {
            switch result {
            case let .verified(transaction):
                if enqueueTransaction(transaction) {
                    count += 1
                    // Flush periodically so a large backlog never overflows the queue.
                    if count.isMultiple(of: Self.scanFlushBatchSize) {
                        await sendEnqueuedEvents()
                    }
                }
            case let .unverified(_, error):
                Logger.log("Unverified transaction: \(error)", level: .error)
            }
        }
        if count > 0 {
            Logger.log("Scanned \(count) new transaction(s), sending batch", level: .debug)
            await sendEnqueuedEvents()
        }
    }

    // MARK: - Network

    /// Sends all events currently in the persistent queue.
    ///
    /// Serialized via `_isSending` flag — concurrent callers return immediately.
    /// After a successful send, re-checks the queue to drain events that were
    /// enqueued during the network call. Lock interactions live in sync helpers
    /// so they're never reached from an async context (Swift 6 strict-concurrency).
    private func sendEnqueuedEvents() async {
        guard tryAcquireSend() else { return }
        defer { releaseSend() }

        // Loop to drain events enqueued while a send was in-flight.
        while true {
            let pending = eventQueue.peek()
            guard !pending.isEmpty else { return }

            let request = EventsRequest(
                events: pending,
                userId: resolveLinkageUserId(),
                externalUserId: resolveExternalUserId(),
                bundleId: Bundle.main.bundleIdentifier ?? "unknown"
            )

            do {
                let response = try await apiClient.sendEvents(request)
                eventQueue.remove(count: pending.count)
                markSent(pending.map(\.transactionId))
                Logger.log("Sent \(response.processed) purchase event(s)", level: .debug)
                // Loop back to check for newly enqueued events
            } catch {
                Logger.log("Failed to send purchase events, will retry next session: \(error)", level: .error)
                return
            }
        }
    }

    /// Atomically claims the send slot. Returns `false` if a send is already in flight.
    private func tryAcquireSend() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_isSending else { return false }
        _isSending = true
        return true
    }

    /// Releases the send slot. Pairs with a successful ``tryAcquireSend()``.
    private func releaseSend() {
        lock.lock()
        defer { lock.unlock() }
        _isSending = false
    }

    // MARK: - Helpers

    /// Atomic dedup: returns `true` if the transaction is new (not already sent or queued
    /// this session) and records it as pending; returns `false` otherwise.
    ///
    /// A transaction is "already handled" if it's in the persisted `sentTransactionIds`
    /// (confirmed sent) or the in-memory `_pendingTransactionIds` (enqueued this session
    /// but not yet sent). IDs are only persisted as sent after a successful network send
    /// (see ``markSent(_:)``), so an event evicted from the bounded `EventQueue` before
    /// sending is recovered on the next launch instead of being permanently dropped.
    private func markTransactionIfNew(_ transactionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if defaults.sentTransactionIds.contains(transactionId)
            || _pendingTransactionIds.contains(transactionId)
        {
            Logger.log("Transaction already handled: \(transactionId)", level: .debug)
            return false
        }
        _pendingTransactionIds.insert(transactionId)
        return true
    }

    /// Persists transaction IDs as confirmed-sent after a successful network send and
    /// clears them from the in-memory pending set. The 1000-cap evicts arbitrary older
    /// IDs (never the just-sent ones) to bound storage; re-sending an evicted transaction
    /// later is harmless because the backend is idempotent.
    private func markSent(_ transactionIds: [String]) {
        guard !transactionIds.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var sentIds = defaults.sentTransactionIds
        let justSent = Set(transactionIds)
        for id in transactionIds {
            sentIds.insert(id)
            _pendingTransactionIds.remove(id)
        }
        while sentIds.count > 1000, let evictable = sentIds.first(where: { !justSent.contains($0) }) {
            sentIds.remove(evictable)
        }
        defaults.sentTransactionIds = sentIds
    }

    /// Stable device-scoped linkage identity — ALWAYS the anonymous SpendOwl ID,
    /// so purchases match the install's attribution regardless of `setUserId`.
    private func resolveLinkageUserId() -> String {
        KeychainHelper.shared.getOrCreateAnonymousId()
    }

    /// Optional developer-supplied identifier (reporting metadata only), or `nil`.
    private func resolveExternalUserId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return _externalUserId
    }

    private func resolveEnvironmentFromReceipt() -> String {
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           receiptURL.lastPathComponent == "sandboxReceipt"
        {
            return "sandbox"
        }
        return "production"
    }

    private func resolveEnvironment(for transaction: Transaction) -> String {
        if #available(iOS 16.0, macOS 13.0, *) {
            return transaction.environment == .production ? "production" : "sandbox"
        }
        // iOS 15: use the app receipt URL path to detect sandbox
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           receiptURL.lastPathComponent == "sandboxReceipt"
        {
            return "sandbox"
        }
        return "production"
    }
}

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

        /// Current depth of the persistent event queue.
        var pendingCountForTesting: Int {
            eventQueue.pendingCount
        }
    }
#endif
