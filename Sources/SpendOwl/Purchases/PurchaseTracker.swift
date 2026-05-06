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
/// 3. `Transaction.currentEntitlements` — startup safety net for missed purchases
///
/// Deduplication is handled atomically via `sentTransactionIds` (transactionId-based).
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
    private var _userId: String?
    private var _isSending = false

    // MARK: - Initialization

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        eventQueue = EventQueue()
        super.init()
    }

    // MARK: - Public Methods

    /// Sets the user ID for purchase attribution.
    ///
    /// - Parameter userId: The user ID to associate with purchases.
    func setUserId(_ userId: String?) {
        lock.lock()
        defer { lock.unlock() }
        _userId = userId
    }

    /// Starts fully automatic purchase tracking.
    ///
    /// 1. Registers `SKPaymentTransactionObserver` (sync — immediately active)
    /// 2. Flushes pending events and scans `currentEntitlements` (async)
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
            await scanCurrentEntitlements()
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

    // MARK: - Current Entitlements Scan

    /// Scans `Transaction.currentEntitlements` as a safety net for missed purchases.
    /// Batches all new events, then sends once to avoid per-entitlement network calls.
    private func scanCurrentEntitlements() async {
        Logger.log("Scanning current entitlements", level: .debug)
        var count = 0
        for await result in Transaction.currentEntitlements {
            switch result {
            case let .verified(transaction):
                if enqueueTransaction(transaction) { count += 1 }
            case let .unverified(_, error):
                Logger.log("Unverified transaction: \(error)", level: .error)
            }
        }
        if count > 0 {
            Logger.log("Scanned \(count) new entitlement(s), sending batch", level: .debug)
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

            let effectiveUserId = resolveUserId()

            let request = EventsRequest(
                events: pending,
                userId: effectiveUserId,
                bundleId: Bundle.main.bundleIdentifier ?? "unknown"
            )

            do {
                let response = try await apiClient.sendEvents(request)
                eventQueue.remove(count: pending.count)
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

    /// Atomic dedup: returns `true` if the transaction is new and was marked.
    /// Returns `false` if already sent. The 1000-cap evicts an arbitrary ID
    /// (but never the newly inserted one) to prevent unbounded growth.
    /// Duplicates from eviction are harmless — the backend is idempotent.
    private func markTransactionIfNew(_ transactionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var sentIds = defaults.sentTransactionIds
        if sentIds.contains(transactionId) {
            Logger.log("Transaction already sent: \(transactionId)", level: .debug)
            return false
        }
        sentIds.insert(transactionId)
        if sentIds.count > 1000, let oldest = sentIds.first(where: { $0 != transactionId }) {
            sentIds.remove(oldest)
        }
        defaults.sentTransactionIds = sentIds
        return true
    }

    private func resolveUserId() -> String {
        lock.lock()
        let uid = _userId
        lock.unlock()
        return uid ?? KeychainHelper.shared.getOrCreateAnonymousId()
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
