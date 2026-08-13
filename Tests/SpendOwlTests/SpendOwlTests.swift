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
        defaults.pendingAttributionData = Data([7, 8, 9])

        defaults.reset()

        XCTAssertFalse(defaults.attributionSent)
        XCTAssertNil(defaults.attributionStatus)
        XCTAssertTrue(defaults.sentTransactionIds.isEmpty)
        XCTAssertNil(defaults.cachedAttributionResult)
        XCTAssertNil(defaults.pendingEventsData)
        XCTAssertNil(defaults.pendingAttributionData)
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

    func testDefaultsPendingAttributionData() {
        let defaults = Defaults.shared

        XCTAssertNil(defaults.pendingAttributionData)

        let data = Data("{\"attributionToken\": \"abc\"}".utf8)
        defaults.pendingAttributionData = data
        XCTAssertEqual(defaults.pendingAttributionData, data)

        defaults.pendingAttributionData = nil
        XCTAssertNil(defaults.pendingAttributionData)
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

    /// `Defaults` stores whatever it is given — the cap lives in `PurchaseTracker` — and
    /// must preserve order, which is what makes oldest-first eviction possible.
    func testSentTransactionIdsRoundTripPreservesOrder() {
        let defaults = Defaults.shared

        let ids = (0 ..< 1050).map { "bound-tx-\($0)" }
        defaults.sentTransactionIds = ids

        let stored = defaults.sentTransactionIds
        XCTAssertEqual(stored.count, 1050)
        XCTAssertEqual(stored, ids, "order must survive the round trip")
    }

    func testDefaultsConcurrentAccess() {
        let defaults = Defaults.shared
        let iterations = 1000
        let expectation = expectation(description: "concurrent defaults")
        expectation.expectedFulfillmentCount = iterations * 2

        for i in 0 ..< iterations {
            DispatchQueue.global().async {
                defaults.sentTransactionIds = ["tx\(i)"]
                expectation.fulfill()
            }
            DispatchQueue.global().async {
                _ = defaults.sentTransactionIds
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)
    }
}
