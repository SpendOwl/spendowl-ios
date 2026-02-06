//
//  PurchaseTracker.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
import StoreKit

/// Internal service for observing and tracking StoreKit 2 transactions.
///
/// Automatically observes `Transaction.updates` and sends purchase events
/// to the SpendOwl backend for ROAS calculation.
@available(iOS 15.0, macOS 12.0, *)
final class PurchaseTracker: @unchecked Sendable {
    // MARK: - Properties

    private let apiClient: APIClient
    private let defaults = Defaults.shared
    private let eventQueue: EventQueue
    private let lock = NSLock()
    private var updateTask: Task<Void, Never>?
    private var _userId: String?

    // MARK: - Initialization

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        eventQueue = EventQueue()
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

    /// Starts observing StoreKit transaction updates.
    ///
    /// This method is called automatically when the SDK is configured.
    /// Transactions are observed for the lifetime of the app.
    func startObserving() {
        lock.lock()
        guard updateTask == nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Flush any pending events from previous sessions
        Task { [weak self] in
            await self?.flushPendingEvents()
        }

        let task = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                await handleTransactionResult(result)
            }
        }

        lock.lock()
        updateTask = task
        lock.unlock()

        Logger.log("Started observing StoreKit transactions", level: .debug)
    }

    /// Stops observing transactions.
    ///
    /// This is typically only called during testing or when the SDK is reset.
    func stopObserving() {
        lock.lock()
        updateTask?.cancel()
        updateTask = nil
        lock.unlock()
        Logger.log("Stopped observing StoreKit transactions", level: .debug)
    }

    // MARK: - Transaction Handling

    private func handleTransactionResult(_ result: VerificationResult<Transaction>) async {
        switch result {
        case let .verified(transaction):
            await recordTransaction(transaction)
            await transaction.finish()

        case let .unverified(transaction, error):
            Logger.log("Unverified transaction \(transaction.id): \(error)", level: .error)
            // Still finish to prevent re-delivery
            await transaction.finish()
        }
    }

    private func recordTransaction(_ transaction: Transaction) async {
        let transactionId = String(transaction.id)

        // Atomic deduplication check+store
        let alreadySent: Bool = {
            lock.lock()
            defer { lock.unlock() }
            return defaults.sentTransactionIds.contains(transactionId)
        }()

        guard !alreadySent else {
            Logger.log("Transaction already sent: \(transactionId)", level: .debug)
            return
        }

        // Fetch product info for price
        var priceString: String?
        var currencyCode: String?
        var countryCode: String?

        if let product = try? await Product.products(for: [transaction.productID]).first {
            priceString = "\(product.price)"
            currencyCode = product.priceFormatStyle.currencyCode
        }

        // Get storefront for country
        if let storefront = await Storefront.current {
            countryCode = storefront.countryCode
        }

        // Determine environment
        let environmentString = resolveEnvironment(for: transaction)

        let event = PurchaseEvent(
            type: eventType(for: transaction),
            transactionId: transactionId,
            originalTransactionId: transaction.originalID != transaction.id ? String(transaction.originalID) : nil,
            productId: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            price: priceString,
            currency: currencyCode,
            countryCode: countryCode,
            quantity: transaction.purchasedQuantity,
            environment: environmentString
        )

        await sendEvents([event])

        // Atomically mark as sent with bounded storage
        markTransactionSent(transactionId)

        Logger.log("Recorded transaction: \(transactionId) (\(event.type))", level: .info)
    }

    private func eventType(for transaction: Transaction) -> String {
        switch transaction.productType {
        case .autoRenewable:
            transaction.originalID == transaction.id ? "subscription_start" : "subscription_renewal"
        case .consumable:
            "consumable_purchase"
        case .nonConsumable:
            "non_consumable_purchase"
        case .nonRenewable:
            "non_renewable_purchase"
        default:
            "purchase"
        }
    }

    private func sendEvents(_ events: [PurchaseEvent]) async {
        guard !events.isEmpty else { return }

        // Always send a user ID - either developer-set or anonymous
        let effectiveUserId = resolveUserId()

        let request = EventsRequest(
            events: events,
            userId: effectiveUserId,
            bundleId: Bundle.main.bundleIdentifier ?? "unknown"
        )

        do {
            let response = try await apiClient.sendEvents(request)
            Logger.log("Sent \(response.processed) purchase event(s)", level: .debug)

            // On success, also try to flush any previously queued events
            await flushPendingEvents()
        } catch {
            Logger.log("Failed to send purchase events: \(error)", level: .error)
            eventQueue.enqueue(events)
        }
    }

    private func flushPendingEvents() async {
        let pending = eventQueue.peek()
        guard !pending.isEmpty else { return }

        Logger.log("Flushing \(pending.count) pending events", level: .debug)

        let effectiveUserId = resolveUserId()

        let request = EventsRequest(
            events: pending,
            userId: effectiveUserId,
            bundleId: Bundle.main.bundleIdentifier ?? "unknown"
        )

        do {
            let response = try await apiClient.sendEvents(request)
            eventQueue.remove(count: pending.count)
            Logger.log("Flushed \(response.processed) pending event(s)", level: .debug)
        } catch {
            Logger.log("Failed to flush pending events: \(error)", level: .error)
        }
    }

    // MARK: - Helpers

    private func markTransactionSent(_ transactionId: String) {
        lock.lock()
        defer { lock.unlock() }
        var sentIds = defaults.sentTransactionIds
        sentIds.insert(transactionId)
        if sentIds.count > 1000 {
            sentIds = Set(sentIds.suffix(1000))
        }
        defaults.sentTransactionIds = sentIds
    }

    private func resolveUserId() -> String {
        lock.lock()
        let uid = _userId
        lock.unlock()
        return uid ?? KeychainHelper.shared.getOrCreateAnonymousId()
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
