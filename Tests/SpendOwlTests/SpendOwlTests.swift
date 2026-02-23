//
//  SpendOwlTests.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

@testable import SpendOwl
import XCTest

@available(iOS 15.0, macOS 12.0, *)
final class SpendOwlTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Defaults.shared.reset()
    }

    // MARK: - Configuration

    func testConfigurationCreation() {
        let config = SpendOwlConfiguration(apiKey: "test_key")

        XCTAssertEqual(config.apiKey, "test_key")
        XCTAssertEqual(config.timeoutInterval, 10)
        XCTAssertEqual(config.maxRetries, 3)
    }

    func testConfigurationCustomValues() throws {
        let config = try SpendOwlConfiguration(
            apiKey: "test_key",
            baseURL: XCTUnwrap(URL(string: "https://custom.api.com")),
            timeoutInterval: 30,
            maxRetries: 5
        )

        XCTAssertEqual(config.apiKey, "test_key")
        XCTAssertEqual(config.baseURL.absoluteString, "https://custom.api.com")
        XCTAssertEqual(config.timeoutInterval, 30)
        XCTAssertEqual(config.maxRetries, 5)
    }

    // MARK: - Defaults Storage

    func testDefaultsStorage() {
        let defaults = Defaults.shared

        XCTAssertFalse(defaults.attributionSent)
        defaults.attributionSent = true
        XCTAssertTrue(defaults.attributionSent)

        XCTAssertNil(defaults.attributionStatus)
        defaults.attributionStatus = "attributed"
        XCTAssertEqual(defaults.attributionStatus, "attributed")

        XCTAssertTrue(defaults.sentTransactionIds.isEmpty)
        defaults.sentTransactionIds = ["tx1", "tx2"]
        XCTAssertEqual(defaults.sentTransactionIds, ["tx1", "tx2"])
    }

    func testDefaultsReset() {
        let defaults = Defaults.shared

        defaults.attributionSent = true
        defaults.attributionStatus = "organic"
        defaults.sentTransactionIds = ["tx1"]
        defaults.cachedAttributionResult = Data([1, 2, 3])
        defaults.pendingEventsData = Data([4, 5, 6])

        defaults.reset()

        XCTAssertFalse(defaults.attributionSent)
        XCTAssertNil(defaults.attributionStatus)
        XCTAssertTrue(defaults.sentTransactionIds.isEmpty)
        XCTAssertNil(defaults.cachedAttributionResult)
        XCTAssertNil(defaults.pendingEventsData)
    }

    func testDefaultsCachedAttributionResult() {
        let defaults = Defaults.shared

        XCTAssertNil(defaults.cachedAttributionResult)

        let data = Data("{\"test\": true}".utf8)
        defaults.cachedAttributionResult = data
        XCTAssertEqual(defaults.cachedAttributionResult, data)

        defaults.cachedAttributionResult = nil
        XCTAssertNil(defaults.cachedAttributionResult)
    }

    func testDefaultsPendingEventsData() {
        let defaults = Defaults.shared

        XCTAssertNil(defaults.pendingEventsData)

        let data = Data("[{\"event\": 1}]".utf8)
        defaults.pendingEventsData = data
        XCTAssertEqual(defaults.pendingEventsData, data)

        defaults.pendingEventsData = nil
        XCTAssertNil(defaults.pendingEventsData)
    }

    // MARK: - Logger

    func testLoggerLevels() {
        XCTAssertTrue(Logger.Level.error < Logger.Level.info)
        XCTAssertTrue(Logger.Level.info < Logger.Level.debug)
        XCTAssertTrue(Logger.Level.none < Logger.Level.error)
    }

    // MARK: - SpendOwlError

    func testSpendOwlErrorDescriptions() {
        XCTAssertNotNil(SpendOwlError.notConfigured.errorDescription)
        XCTAssertNotNil(SpendOwlError.invalidAPIKey.errorDescription)
        XCTAssertNotNil(SpendOwlError.attributionUnavailable.errorDescription)
        XCTAssertNotNil(SpendOwlError.attributionDenied.errorDescription)
        XCTAssertNotNil(SpendOwlError.encodingError.errorDescription)

        let networkError = SpendOwlError.networkError(URLError(.notConnectedToInternet))
        XCTAssertTrue(networkError.errorDescription?.contains("Network error") ?? false)

        let serverError = SpendOwlError.serverError(statusCode: 500, message: "Internal error")
        XCTAssertTrue(serverError.errorDescription?.contains("500") ?? false)
    }

    func testSpendOwlErrorCodes() {
        XCTAssertEqual(SpendOwlError.notConfigured.errorCode, 1001)
        XCTAssertEqual(SpendOwlError.invalidAPIKey.errorCode, 1002)
        XCTAssertEqual(SpendOwlError.networkError(URLError(.unknown)).errorCode, 2001)
        XCTAssertEqual(SpendOwlError.serverError(statusCode: 500, message: nil).errorCode, 2002)
        XCTAssertEqual(SpendOwlError.attributionUnavailable.errorCode, 3001)
        XCTAssertEqual(SpendOwlError.attributionDenied.errorCode, 3002)
        XCTAssertEqual(SpendOwlError.encodingError.errorCode, 4001)
        XCTAssertEqual(SpendOwlError.decodingError(URLError(.unknown)).errorCode, 4002)
        XCTAssertEqual(SpendOwlError.unknown(URLError(.unknown)).errorCode, 9999)
    }

    func testSpendOwlErrorEquatable() {
        XCTAssertEqual(SpendOwlError.notConfigured, SpendOwlError.notConfigured)
        XCTAssertNotEqual(SpendOwlError.notConfigured, SpendOwlError.invalidAPIKey)
        XCTAssertEqual(
            SpendOwlError.networkError(URLError(.timedOut)),
            SpendOwlError.networkError(URLError(.notConnectedToInternet))
        )
    }

    // MARK: - AttributionStatus

    func testAttributionStatus() {
        XCTAssertEqual(AttributionStatus(rawValue: "attributed"), .attributed)
        XCTAssertEqual(AttributionStatus(rawValue: "organic"), .organic)
        XCTAssertEqual(AttributionStatus(rawValue: "unknown"), .unknown)
        XCTAssertNil(AttributionStatus(rawValue: "invalid"))
    }

    func testAttributionStatusCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in [AttributionStatus.attributed, .organic, .unknown] {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(AttributionStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    // MARK: - AttributionResult

    func testAttributionResultCodable() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = AttributionResult(
            id: "test-123",
            status: .attributed,
            campaignId: 42,
            campaignName: "Campaign A",
            adGroupId: 7,
            adGroupName: "Ad Group B",
            keywordId: 99,
            keyword: "fitness app",
            countryOrRegion: "US",
            clickDate: Date(timeIntervalSince1970: 1_700_000_000),
            conversionType: "Download",
            supplyPlacement: "top_of_search"
        )

        let data = try encoder.encode(result)
        let decoded = try decoder.decode(AttributionResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    func testAttributionResultEquatableAllFields() {
        let result1 = AttributionResult(
            id: "test-1",
            status: .attributed,
            campaignId: 1,
            campaignName: "Camp",
            adGroupId: 2,
            adGroupName: "Group",
            keywordId: 3,
            keyword: "kw",
            countryOrRegion: "US",
            clickDate: Date(timeIntervalSince1970: 1_000_000),
            conversionType: "Download",
            supplyPlacement: "top_of_search"
        )

        let result2 = AttributionResult(
            id: "test-1",
            status: .attributed,
            campaignId: 1,
            campaignName: "Camp",
            adGroupId: 2,
            adGroupName: "Group",
            keywordId: 3,
            keyword: "kw",
            countryOrRegion: "US",
            clickDate: Date(timeIntervalSince1970: 1_000_000),
            conversionType: "Download",
            supplyPlacement: "top_of_search"
        )

        XCTAssertEqual(result1, result2)
    }

    func testAttributionResultEquatableDifferentFields() {
        let base = AttributionResult(
            id: "test-1",
            status: .attributed,
            campaignId: 1,
            campaignName: "Camp",
            adGroupId: nil,
            adGroupName: nil,
            keywordId: nil,
            keyword: nil,
            countryOrRegion: "US",
            clickDate: nil,
            conversionType: nil,
            supplyPlacement: nil
        )

        // Same id but different campaignName — should NOT be equal
        let different = AttributionResult(
            id: "test-1",
            status: .attributed,
            campaignId: 1,
            campaignName: "Different Camp",
            adGroupId: nil,
            adGroupName: nil,
            keywordId: nil,
            keyword: nil,
            countryOrRegion: "US",
            clickDate: nil,
            conversionType: nil,
            supplyPlacement: nil
        )

        XCTAssertNotEqual(base, different)
    }

    func testAttributionResultDecodesNils() throws {
        let json = """
        {"id": "organic-1", "status": "organic"}
        """
        let decoder = JSONDecoder()
        let result = try decoder.decode(AttributionResult.self, from: Data(json.utf8))

        XCTAssertEqual(result.id, "organic-1")
        XCTAssertEqual(result.status, .organic)
        XCTAssertNil(result.campaignId)
        XCTAssertNil(result.campaignName)
        XCTAssertNil(result.adGroupId)
        XCTAssertNil(result.keyword)
        XCTAssertNil(result.clickDate)
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

    // MARK: - KeychainHelper

    func testKeychainSetAndGet() {
        let keychain = KeychainHelper.shared

        // Clean up first
        keychain.delete("test_key")

        let success = keychain.set("hello", forKey: "test_key")
        XCTAssertTrue(success)

        let value = keychain.get("test_key")
        XCTAssertEqual(value, "hello")

        // Clean up
        keychain.delete("test_key")
    }

    func testKeychainOverwrite() {
        let keychain = KeychainHelper.shared
        keychain.delete("test_key")

        keychain.set("first", forKey: "test_key")
        keychain.set("second", forKey: "test_key")

        XCTAssertEqual(keychain.get("test_key"), "second")
        keychain.delete("test_key")
    }

    func testKeychainDelete() {
        let keychain = KeychainHelper.shared

        keychain.set("value", forKey: "test_delete")
        XCTAssertNotNil(keychain.get("test_delete"))

        let deleted = keychain.delete("test_delete")
        XCTAssertTrue(deleted)
        XCTAssertNil(keychain.get("test_delete"))
    }

    func testKeychainDeleteNonExistent() {
        let keychain = KeychainHelper.shared

        // Deleting a non-existent key should return true (errSecItemNotFound is OK)
        let result = keychain.delete("nonexistent_key_\(UUID().uuidString)")
        XCTAssertTrue(result)
    }

    func testKeychainGetNonExistent() {
        let keychain = KeychainHelper.shared
        let value = keychain.get("nonexistent_key_\(UUID().uuidString)")
        XCTAssertNil(value)
    }

    func testAnonymousIdFormat() {
        let keychain = KeychainHelper.shared
        // Delete existing to force creation
        keychain.delete("anonymous_id")

        let id = keychain.getOrCreateAnonymousId()
        XCTAssertTrue(id.hasPrefix("$SpendOwlID:"))
        XCTAssertEqual(id.count, "$SpendOwlID:".count + 36) // UUID is 36 chars with hyphens

        // Second call should return the same value
        let id2 = keychain.getOrCreateAnonymousId()
        XCTAssertEqual(id, id2)

        // Clean up
        keychain.delete("anonymous_id")
    }

    // MARK: - APIClient Helpers

    func testSanitizedKeyLong() {
        let result = APIClient.sanitizedKey("spendowl_live_abcdefgh1234")
        XCTAssertEqual(result, "spen***1234")
        XCTAssertFalse(result.contains("abcdefgh"))
    }

    func testSanitizedKeyShort() {
        let result = APIClient.sanitizedKey("short")
        XCTAssertEqual(result, "***")
    }

    func testSanitizedKeyExactly8() {
        let result = APIClient.sanitizedKey("12345678")
        XCTAssertEqual(result, "***")
    }

    func testSanitizedKey9Chars() {
        let result = APIClient.sanitizedKey("123456789")
        XCTAssertEqual(result, "1234***6789")
    }

    // MARK: - SDK Version

    func testSDKVersionNotEmpty() {
        XCTAssertFalse(SpendOwl.sdkVersion.isEmpty)
    }

    func testSDKVersionFormat() {
        // Should be semver-like: digits.digits.digits
        let parts = SpendOwl.sdkVersion.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        for part in parts {
            XCTAssertNotNil(Int(part))
        }
    }

    // MARK: - Thread Safety

    func testSentTransactionIdsBoundedAt1000() {
        let defaults = Defaults.shared

        // Insert 1050 IDs
        var ids = Set<String>()
        for i in 0 ..< 1050 {
            ids.insert("bound-tx-\(i)")
        }
        defaults.sentTransactionIds = ids

        // Read back — Defaults stores the raw set; PurchaseTracker enforces the 1000 cap.
        // Here we verify Defaults faithfully round-trips even a large set.
        let stored = defaults.sentTransactionIds
        XCTAssertEqual(stored.count, 1050)
    }

    func testDefaultsConcurrentAccess() {
        let defaults = Defaults.shared
        let iterations = 1000
        let expectation = expectation(description: "concurrent defaults")
        expectation.expectedFulfillmentCount = iterations * 2

        for i in 0 ..< iterations {
            DispatchQueue.global().async {
                defaults.sentTransactionIds = Set(["tx\(i)"])
                expectation.fulfill()
            }
            DispatchQueue.global().async {
                _ = defaults.sentTransactionIds
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)
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
