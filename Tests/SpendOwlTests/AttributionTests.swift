//
//  AttributionTests.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

@testable import SpendOwl
import XCTest

@available(iOS 15.0, macOS 12.0, *)
final class AttributionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Defaults.shared.reset()
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

    // MARK: - AttributionQueue

    func testAttributionQueueLoadEmpty() {
        let queue = AttributionQueue()
        XCTAssertNil(queue.load())
        XCTAssertFalse(queue.hasPending)
    }

    func testAttributionQueueSaveLoadClear() {
        let queue = AttributionQueue()
        let pending = makePending(token: "tok-1")

        queue.save(pending)
        XCTAssertTrue(queue.hasPending)

        let loaded = queue.load()
        XCTAssertEqual(loaded, pending)

        queue.clear()
        XCTAssertNil(queue.load())
        XCTAssertFalse(queue.hasPending)
    }

    func testAttributionQueueOverwrites() {
        let queue = AttributionQueue()
        queue.save(makePending(token: "first"))
        queue.save(makePending(token: "second"))

        XCTAssertEqual(queue.load()?.attributionToken, "second")
    }

    func testAttributionQueuePersistsAcrossInstances() {
        let queue1 = AttributionQueue()
        queue1.save(makePending(token: "persisted"))

        let queue2 = AttributionQueue()
        XCTAssertEqual(queue2.load()?.attributionToken, "persisted")
    }

    func testAttributionQueueDropsCorruptData() {
        Defaults.shared.pendingAttributionData = Data("not json".utf8)

        let queue = AttributionQueue()
        XCTAssertNil(queue.load())
        XCTAssertFalse(queue.hasPending)
        // Corrupt data should have been wiped on the failed load.
        XCTAssertNil(Defaults.shared.pendingAttributionData)
    }

    func testPendingAttributionCodableRoundTrip() throws {
        let pending = makePending(token: "round-trip")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(pending)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PendingAttribution.self, from: data)

        XCTAssertEqual(decoded, pending)
    }

    func testPendingAttributionDecodesLegacyWithoutExternalUserId() throws {
        // A payload persisted by an older SDK has no externalUserId field; the
        // optional must decode to nil rather than failing.
        let legacy = Data("""
        {"attributionToken":"t","bundleId":"com.test.app","appVersion":"1.0.0",\
        "sdkVersion":"1.2.0","userId":"user-1","osVersion":"17.0.0",\
        "deviceModel":"iPhone16,1","locale":"en_US",\
        "createdAt":"2023-11-14T22:13:20Z"}
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PendingAttribution.self, from: legacy)

        XCTAssertNil(decoded.externalUserId)
        XCTAssertEqual(decoded.userId, "user-1")
    }

    // MARK: - AttributionService External User ID

    func testFetchAttributionSendsAnonymousLinkageAndExternalId() async throws {
        let captured = CapturedRequest()
        let service = makeServiceFor(
            tokenProvider: { "tok" },
            sender: { request in
                captured.set(request)
                return self.makeStubResult(id: "s1", status: .attributed)
            }
        )

        _ = try await service.fetchAttribution(userId: "anon-1", externalUserId: "dev-1")

        // Linkage id is sent as userId; the developer id rides along separately.
        XCTAssertEqual(captured.value?.userId, "anon-1")
        XCTAssertEqual(captured.value?.externalUserId, "dev-1")
    }

    /// The host app's opt-in has to reach the server, because the only other signal — the
    /// console warning — is off by default and compiled out of release builds, so it never
    /// leaves the developer's machine.
    func testForwardsConsumableHistoryOptIn() async throws {
        let captured = CapturedRequest()
        let service = makeServiceFor(
            tokenProvider: { "tok" },
            sender: { request in
                captured.set(request)
                return self.makeStubResult(id: "s1", status: .attributed)
            }
        )

        _ = try await service.fetchAttribution(userId: "anon-1")

        // The test host has no such key, so this pins the absent-key default reaching the
        // wire rather than being dropped or defaulting to true somewhere along the way.
        XCTAssertEqual(captured.value?.consumableHistoryEnabled, false)
        XCTAssertEqual(captured.value?.consumableHistoryEnabled, ConsumableHistory.isEnabled)
    }

    /// A pending payload can be days old and the app may have shipped an update since, so
    /// the opt-in must be read at replay time — like the identity fields, and unlike the
    /// token and device info, which describe the original install.
    func testReplayReadsConsumableHistoryOptInFresh() async throws {
        let queue = AttributionQueue()
        queue.save(makePending(token: "leftover"))

        let captured = CapturedRequest()
        let service = makeServiceFor(
            queue: queue,
            tokenProvider: { XCTFail("Replay must not fetch a fresh token"); return "" },
            sender: { request in
                captured.set(request)
                return self.makeStubResult(id: "s1", status: .attributed)
            }
        )

        _ = try await service.fetchAttribution(userId: "u1")

        XCTAssertEqual(captured.value?.consumableHistoryEnabled, ConsumableHistory.isEnabled)
    }

    // MARK: - AttributionService Token Retry

    func testTokenRetrySucceedsOnSecondAttempt() async {
        let attempts = AtomicCounter()
        let service = makeServiceFor(
            tokenProvider: {
                let n = attempts.increment()
                if n == 1 {
                    throw NSError(domain: "AAAttributionErrorDomain", code: 1)
                }
                return "ok-token"
            },
            sender: { _ in throw URLError(.notConnectedToInternet) }
        )

        do {
            _ = try await service.fetchAttribution(userId: "u1")
        } catch {
            // Expected — sender stub throws so we can confirm we reached the network step.
        }

        XCTAssertEqual(attempts.value, 2, "Token provider should be called twice (1 fail, 1 success)")
    }

    func testTokenRetryExhaustsAndMapsNetworkError() async {
        let attempts = AtomicCounter()
        let service = makeServiceFor(tokenProvider: {
            _ = attempts.increment()
            throw NSError(domain: "AAAttributionErrorDomain", code: 1)
        })

        do {
            _ = try await service.fetchAttribution(userId: "u1")
            XCTFail("Should have thrown")
        } catch let error as SpendOwlError {
            XCTAssertEqual(error, .networkError(URLError(.unknown)))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        XCTAssertEqual(attempts.value, 5, "Token provider should be called 5 times")
    }

    func testTokenPlatformNotSupportedShortCircuits() async {
        let attempts = AtomicCounter()
        let service = makeServiceFor(tokenProvider: {
            _ = attempts.increment()
            throw NSError(domain: "AAAttributionErrorDomain", code: 3)
        })

        do {
            _ = try await service.fetchAttribution(userId: "u1")
            XCTFail("Should have thrown")
        } catch let error as SpendOwlError {
            XCTAssertEqual(error, .attributionUnavailable)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        // Code 3 is permanent — must not retry.
        XCTAssertEqual(attempts.value, 1)
    }

    // MARK: - AttributionService Queue Replay

    func testReplaySucceedsAndClearsQueue() async throws {
        // A pending payload from a prior launch.
        let pending = makePending(token: "leftover")
        let queue = AttributionQueue()
        queue.save(pending)

        let stubResult = makeStubResult(id: "stub-1", status: .attributed)
        let attempts = AtomicCounter()

        let service = makeServiceFor(
            queue: queue,
            tokenProvider: {
                _ = attempts.increment()
                return "fresh-token"
            },
            sender: { request in
                XCTAssertEqual(
                    request.attributionToken,
                    pending.attributionToken,
                    "Replay should send the persisted token, not a fresh one"
                )
                return stubResult
            }
        )

        let result = try await service.fetchAttribution(userId: "u1")

        XCTAssertEqual(result.id, "stub-1")
        XCTAssertEqual(attempts.value, 0, "Token provider must not be called when replay succeeds")
        XCTAssertFalse(queue.hasPending, "Queue should be cleared after a successful replay")
        XCTAssertTrue(Defaults.shared.attributionSent)
    }

    func testFailedSendRetainsPendingPayload() async {
        // Empty queue: a fresh fetch will run, persist a payload, then fail to send.
        let queue = AttributionQueue()
        XCTAssertFalse(queue.hasPending)

        let service = makeServiceFor(
            queue: queue,
            tokenProvider: { "fresh-token" },
            sender: { _ in throw URLError(.notConnectedToInternet) }
        )

        do {
            _ = try await service.fetchAttribution(userId: "u1")
            XCTFail("Should have thrown")
        } catch {
            // Expected — sender always throws.
        }

        XCTAssertTrue(queue.hasPending, "Pending payload must remain on disk for next-launch replay")
        XCTAssertEqual(queue.load()?.attributionToken, "fresh-token")
        XCTAssertFalse(Defaults.shared.attributionSent)
    }

    // MARK: - Test Helpers

    private func makePending(token: String) -> PendingAttribution {
        PendingAttribution(
            attributionToken: token,
            bundleId: "com.test.app",
            appVersion: "1.0.0",
            sdkVersion: "1.2.0",
            userId: "user-1",
            externalUserId: "ext-user-1",
            osVersion: "17.0.0",
            deviceModel: "iPhone16,1",
            locale: "en_US",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeStubResult(id: String, status: AttributionStatus) -> AttributionResult {
        AttributionResult(
            id: id,
            status: status,
            campaignId: 1,
            campaignName: "Stub",
            adGroupId: nil,
            adGroupName: nil,
            keywordId: nil,
            keyword: nil,
            countryOrRegion: "US",
            clickDate: nil,
            conversionType: nil,
            supplyPlacement: nil
        )
    }

    private func makeServiceFor(
        queue: AttributionQueue = AttributionQueue(),
        tokenProvider: @escaping @Sendable () throws -> String,
        sender: (@Sendable (AttributionRequest) async throws -> AttributionResult)? = nil
    ) -> AttributionService {
        let configuration = SpendOwlConfiguration(
            apiKey: "test",
            // swiftlint:disable:next force_unwrapping
            baseURL: URL(string: "http://127.0.0.1:1/api")!,
            timeoutInterval: 1,
            maxRetries: 1
        )
        return AttributionService(
            apiClient: APIClient(configuration: configuration),
            defaults: .shared,
            queue: queue,
            retryDelays: [0, 0, 0, 0],
            sleep: { _ in },
            tokenProvider: tokenProvider,
            sender: sender
        )
    }
}

/// Thread-safe holder that captures the request passed to the sender closure.
@available(iOS 15.0, macOS 12.0, *)
private final class CapturedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: AttributionRequest?

    var value: AttributionRequest? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ request: AttributionRequest) {
        lock.lock()
        defer { lock.unlock() }
        _value = request
    }
}

/// Thread-safe counter used by the token-provider closure in async tests.
@available(iOS 15.0, macOS 12.0, *)
private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }
}
