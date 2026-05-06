//
//  EventQueueTests.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

@testable import SpendOwl
import XCTest

@available(iOS 15.0, macOS 12.0, *)
final class EventQueueTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Defaults.shared.reset()
    }

    // MARK: - EventQueue

    func testEventQueueEnqueueAndPeek() {
        let queue = EventQueue()
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertTrue(queue.peek().isEmpty)

        let events = [makeEvent(id: "tx1"), makeEvent(id: "tx2")]
        queue.enqueue(events)

        XCTAssertEqual(queue.pendingCount, 2)

        let peeked = queue.peek()
        XCTAssertEqual(peeked.count, 2)
        XCTAssertEqual(peeked[0].transactionId, "tx1")
        XCTAssertEqual(peeked[1].transactionId, "tx2")
    }

    func testEventQueueRemove() {
        let queue = EventQueue()
        queue.enqueue([makeEvent(id: "tx1"), makeEvent(id: "tx2"), makeEvent(id: "tx3")])

        queue.remove(count: 2)
        XCTAssertEqual(queue.pendingCount, 1)

        let remaining = queue.peek()
        XCTAssertEqual(remaining[0].transactionId, "tx3")
    }

    func testEventQueueRemoveAll() {
        let queue = EventQueue()
        queue.enqueue([makeEvent(id: "tx1")])

        queue.remove(count: 1)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertTrue(queue.peek().isEmpty)
    }

    func testEventQueueBoundsAt100() {
        let queue = EventQueue()

        // Enqueue 110 events
        let events = (0 ..< 110).map { makeEvent(id: "tx\($0)") }
        queue.enqueue(events)

        // Should trim to 100, dropping the first 10
        XCTAssertEqual(queue.pendingCount, 100)
        let first = queue.peek().first
        XCTAssertEqual(first?.transactionId, "tx10")
    }

    func testEventQueueEmptyEnqueueIsNoop() {
        let queue = EventQueue()
        queue.enqueue([])
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testEventQueueRemoveZeroIsNoop() {
        let queue = EventQueue()
        queue.enqueue([makeEvent(id: "tx1")])
        queue.remove(count: 0)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testEventQueuePersistence() {
        // Enqueue in one instance
        let queue1 = EventQueue()
        queue1.enqueue([makeEvent(id: "tx1")])

        // Read from a new instance (same Defaults)
        let queue2 = EventQueue()
        XCTAssertEqual(queue2.pendingCount, 1)
        XCTAssertEqual(queue2.peek().first?.transactionId, "tx1")
    }

    // MARK: - PurchaseEvent Codable

    func testPurchaseEventCodable() throws {
        let event = makeEvent(id: "tx-100")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PurchaseEvent.self, from: data)

        XCTAssertEqual(decoded.transactionId, "tx-100")
        XCTAssertEqual(decoded.productId, "com.test.product")
        XCTAssertEqual(decoded.type, "consumable_purchase")
        XCTAssertEqual(decoded.price, "4.99")
        XCTAssertEqual(decoded.currency, "USD")
        XCTAssertEqual(decoded.quantity, 1)
        XCTAssertEqual(decoded.environment, "production")
    }

    func testPurchaseEventWithOriginalTransactionId() throws {
        let event = PurchaseEvent(
            type: "subscription_renewal",
            transactionId: "tx-200",
            originalTransactionId: "tx-100",
            productId: "com.test.subscription",
            purchaseDate: Date(timeIntervalSince1970: 1_700_000_000),
            price: "9.99",
            currency: "USD",
            countryCode: "US",
            quantity: 1,
            environment: "sandbox"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PurchaseEvent.self, from: data)

        XCTAssertEqual(decoded.originalTransactionId, "tx-100")
        XCTAssertEqual(decoded.type, "subscription_renewal")
        XCTAssertEqual(decoded.environment, "sandbox")
    }

    func testPurchaseEventNilOptionalFields() throws {
        let event = PurchaseEvent(
            type: "purchase",
            transactionId: "tx-300",
            originalTransactionId: nil,
            productId: "com.test.item",
            purchaseDate: Date(timeIntervalSince1970: 1_700_000_000),
            price: nil,
            currency: nil,
            countryCode: nil,
            quantity: 1,
            environment: "production"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PurchaseEvent.self, from: data)

        XCTAssertNil(decoded.originalTransactionId)
        XCTAssertNil(decoded.price)
        XCTAssertNil(decoded.currency)
        XCTAssertNil(decoded.countryCode)
    }

    // MARK: - Helpers

    private func makeEvent(id: String) -> PurchaseEvent {
        PurchaseEvent(
            type: "consumable_purchase",
            transactionId: id,
            originalTransactionId: nil,
            productId: "com.test.product",
            purchaseDate: Date(timeIntervalSince1970: 1_700_000_000),
            price: "4.99",
            currency: "USD",
            countryCode: "US",
            quantity: 1,
            environment: "production"
        )
    }
}
