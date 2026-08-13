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
/// Uses three complementary listeners:
/// 1. `SKPaymentTransactionObserver` — StoreKit 1 transactions
/// 2. `Transaction.updates` — renewals, cross-device, Ask to Buy, offer codes. Apple does
///    *not* deliver the result of a direct `Product.purchase()` call here.
/// 3. `Transaction.all` — startup safety net that re-emits history a launch may have missed
///
/// Coverage is not uniform across product types, and the gap is structural rather than a
/// bug here: `Transaction.all` omits consumables the app has already finished, so once a
/// consumable is finished the safety net can no longer see it. Subscriptions and
/// non-consumables stay in history and are recovered on any later launch. From iOS 18 the
/// host app can opt back in with `SKIncludeConsumableInAppPurchaseHistory` — see
/// ``ConsumableHistory``, which reports whether this app has.
///
/// Deduplication is atomic and transactionId-based: the persisted `sentTransactionIds`
/// (confirmed sends) combined with an in-memory pending set. An event dropped from the
/// bounded queue before it was sent is therefore re-enqueueable on a later launch — but
/// only for products the scan can still see, which is the same caveat as above.
/// The SDK is fully read-only: neither `transaction.finish()` nor `finishTransaction()` is called.
@available(iOS 15.0, macOS 12.0, *)
final class PurchaseTracker: NSObject, SKPaymentTransactionObserver, @unchecked Sendable {
    // MARK: - Properties

    private let apiClient: APIClient
    private let defaults = Defaults.shared
    let eventQueue: EventQueue
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

        // Surface the consumable-history gap while the developer is integrating, since
        // the SDK cannot close it from here.
        ConsumableHistory.warnIfMissing()

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
    ///
    /// Re-seeds the in-memory pending set from the persisted queue, exactly as `init`
    /// does. IDs claimed by ``markTransactionIfNew(_:)`` but never confirmed sent — and
    /// no longer queued, because the bounded queue evicted them — are released so a
    /// restart in this same process can re-enqueue them instead of silently rejecting
    /// them. IDs still in the queue stay deduped, so the restart cannot queue a second
    /// copy. The `peek()` happens before `lock` is taken so the two locks never nest.
    func stopObserving() {
        let stillQueued = Set(eventQueue.peek().map(\.transactionId))

        lock.lock()
        scanTask?.cancel()
        scanTask = nil
        updateTask?.cancel()
        updateTask = nil
        _pendingTransactionIds = stillQueued
        lock.unlock()

        SKPaymentQueue.default().remove(self)

        Logger.log("Stopped purchase tracking", level: .debug)
    }

    // MARK: - SKPaymentTransactionObserver

    /// Called by StoreKit 1 for every transaction state change.
    ///
    /// Only `.purchased` is recorded. The other states are deliberately ignored:
    ///
    /// - `.restored`: a restore re-delivers a purchase the customer already made, under a
    ///   *new* transaction identifier. It produces no new revenue, and the underlying
    ///   purchase reaches the backend through App Store Server Notifications plus the
    ///   original purchase's own event. Recording it would emit a second purchase event
    ///   for revenue that is already attributed, so we skip it by design rather than by
    ///   omission. Revisit only if restores need to re-link attribution on a new device.
    /// - `.purchasing` / `.deferred`: not yet a purchase; `.deferred` (Ask to Buy) arrives
    ///   as `.purchased` once approved.
    /// - `.failed`: no transaction to attribute.
    ///
    /// `finishTransaction()` is never called (read-only SDK).
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions where transaction.transactionState == .purchased {
            guard let transactionId = transaction.transactionIdentifier else { continue }
            recordStoreKit1Transaction(
                transactionId: transactionId,
                // Mirror StoreKit 2's `Transaction.originalID`, which equals the
                // transaction's own id for an initial purchase and points at the
                // original for a renewal. StoreKit 1 leaves `original` nil on an
                // initial purchase, so fall back to the id to keep both paths
                // joinable against `apple_webhooks.original_transaction_id`.
                originalTransactionId: transaction.original?.transactionIdentifier ?? transactionId,
                productId: transaction.payment.productIdentifier,
                quantity: transaction.payment.quantity,
                date: transaction.transactionDate ?? Date()
            )
        }
    }

    // MARK: - Transaction Recording

    /// Records a purchase observed via `SKPaymentTransactionObserver`.
    func recordStoreKit1Transaction(
        transactionId: String,
        originalTransactionId: String?,
        productId: String,
        quantity: Int,
        date: Date
    ) {
        guard markTransactionIfNew(transactionId) else { return }

        let event = PurchaseEvent(
            type: "purchase",
            transactionId: transactionId,
            originalTransactionId: originalTransactionId,
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
    /// `Transaction.all` returns more than `currentEntitlements` — it includes expired
    /// subscriptions and non-consumables the customer no longer owns — but it is **not**
    /// a complete history. A consumable disappears from it as soon as the app calls
    /// `finish()` on it, which apps typically do the moment they grant the content. So
    /// this scan recovers subscriptions and non-consumables reliably and finished
    /// consumables not at all. On iOS 18+ the host app can opt back in by setting
    /// `SKIncludeConsumableInAppPurchaseHistory`; ``ConsumableHistory`` logs a warning
    /// during development when it hasn't.
    ///
    /// Refunded/revoked entries are included but harmless: the SDK only sends the
    /// attribution↔transaction link, never price or revocation state (those arrive via
    /// App Store Server Notifications on the backend).
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
    /// Lock interactions live in sync helpers so they're never reached from an
    /// async context (Swift 6 strict-concurrency).
    ///
    /// The background-task assertion buys the request time when the user backgrounds
    /// the app right after paying; losing that race costs delay, not data, but the
    /// transaction looks unattributed until the next launch. It is taken after the send
    /// slot is claimed so race losers don't begin one for a no-op, and the drain loop is
    /// extracted so no early return can sit between `begin` and `end` — `defer` cannot
    /// `await`, and a leaked assertion gets the host app terminated.
    func sendEnqueuedEvents() async {
        guard tryAcquireSend() else { return }
        defer { releaseSend() }

        let bgTask = await BackgroundTaskAssertion.begin(name: "SpendOwl.PurchaseEvents")
        await drainEventQueue()
        await bgTask.end()
    }

    /// Builds the payload for a batch of queued events.
    ///
    /// Split out of ``drainEventQueue()`` so tests can assert what goes on the wire without
    /// a network round trip. `consumableHistoryEnabled` is read here rather than cached,
    /// so it reflects the app as it is now — attribution only reports it once per install,
    /// and this is what keeps the value current for apps that add the key in a later
    /// version.
    func makeEventsRequest(for events: [PurchaseEvent]) -> EventsRequest {
        EventsRequest(
            events: events,
            userId: resolveLinkageUserId(),
            externalUserId: resolveExternalUserId(),
            bundleId: Bundle.main.bundleIdentifier ?? "unknown",
            consumableHistoryEnabled: ConsumableHistory.isEnabled
        )
    }

    /// Drains the queue until it is empty or a send fails, re-checking after each success
    /// so events enqueued mid-send go out in the same pass. Caller must hold the send slot.
    private func drainEventQueue() async {
        // Loop to drain events enqueued while a send was in-flight.
        while true {
            let pending = eventQueue.peek()
            guard !pending.isEmpty else { return }

            let request = makeEventsRequest(for: pending)

            do {
                let response = try await apiClient.sendEvents(request)
                // Remove by identity, not by count: events enqueued during the await
                // above shift the queue (and can trim it from the front on overflow),
                // so a positional removal would drop events this send never carried.
                let sentIds = pending.map(\.transactionId)
                eventQueue.remove(transactionIds: sentIds)
                markSent(sentIds)
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
    func markTransactionIfNew(_ transactionId: String) -> Bool {
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

    /// Maximum number of confirmed-sent transaction IDs retained for dedup.
    private static let maxSentTransactionIds = 1000

    /// Persists transaction IDs as confirmed-sent after a successful network send and
    /// clears them from the in-memory pending set.
    ///
    /// The list is append-ordered and the cap evicts from the front, so the entries
    /// dropped are the genuinely oldest. It previously held a `Set` and evicted whatever
    /// `Set.first(where:)` returned — hash order, not age — which could discard an ID
    /// sent minutes ago while keeping one from years back.
    ///
    /// Eviction is not free: an ID that leaves this list is no longer deduped, so if the
    /// transaction is still visible to the startup scan it gets re-enqueued and re-sent.
    /// The backend is idempotent so no duplicate revenue is recorded, but `/v1/events`
    /// re-resolves attribution for that transaction at replay time. Evicting oldest-first
    /// keeps that replay confined to the transactions least likely to still be in
    /// `Transaction.all`.
    func markSent(_ transactionIds: [String]) {
        guard !transactionIds.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var sentIds = defaults.sentTransactionIds
        var known = Set(sentIds)
        for id in transactionIds {
            // Appends only genuinely new IDs, so a repeat send doesn't move an existing
            // entry to the back and outlive newer ones.
            if known.insert(id).inserted {
                sentIds.append(id)
            }
            _pendingTransactionIds.remove(id)
        }

        if sentIds.count > Self.maxSentTransactionIds {
            sentIds.removeFirst(sentIds.count - Self.maxSentTransactionIds)
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
