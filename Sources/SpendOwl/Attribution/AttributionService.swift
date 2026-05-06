//
//  AttributionService.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import AdServices
import Foundation

/// Internal service for retrieving Apple Ads attribution.
///
/// Uses Apple's AdServices framework to obtain an attribution token,
/// which is sent to SpendOwl's backend for processing. The backend
/// calls Apple's API to retrieve the full attribution data.
@available(iOS 15.0, macOS 12.0, *)
final class AttributionService: @unchecked Sendable {
    // MARK: - Properties

    private let defaults: Defaults
    private let queue: AttributionQueue
    /// Delays (in seconds) inserted between consecutive token-fetch attempts.
    /// The first attempt is immediate; element `i` is the wait before attempt
    /// `i + 1`. Total attempts = `retryDelays.count + 1`. Default: 5 attempts
    /// at 0 / 0.5 / 1 / 2 / 4s — every element is used.
    private let retryDelays: [Double]
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let tokenProvider: @Sendable () throws -> String
    private let sender: @Sendable (AttributionRequest) async throws -> AttributionResult

    // MARK: - Initialization

    init(
        apiClient: APIClient,
        defaults: Defaults = .shared,
        queue: AttributionQueue = AttributionQueue(),
        retryDelays: [Double] = [0.5, 1.0, 2.0, 4.0],
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        tokenProvider: @escaping @Sendable () throws -> String = { try AAAttribution.attributionToken() },
        sender: (@Sendable (AttributionRequest) async throws -> AttributionResult)? = nil
    ) {
        self.defaults = defaults
        self.queue = queue
        self.retryDelays = retryDelays
        self.sleep = sleep
        self.tokenProvider = tokenProvider
        self.sender = sender ?? { request in
            try await apiClient.sendAttribution(request)
        }
    }

    // MARK: - Public Methods

    /// Retrieves attribution data from Apple and sends it to the SpendOwl backend.
    ///
    /// - Parameters:
    ///   - userId: Optional user identifier to associate with the attribution.
    ///   - forceRefresh: If `true`, sends attribution even if already sent.
    /// - Returns: The attribution result from the backend.
    /// - Throws: `SpendOwlError` if attribution fails.
    func fetchAttribution(userId: String?, forceRefresh: Bool = false) async throws -> AttributionResult {
        // First, replay any pending attribution from a prior launch. If it
        // succeeds we're done — the install is recorded, regardless of whether
        // the developer explicitly asked for a fresh result.
        if !forceRefresh, let replayed = await replayPendingIfNeeded() {
            return replayed
        }

        // Return cached result if already sent (unless forced)
        if !forceRefresh, defaults.attributionSent {
            if let cached = loadCachedResult() {
                Logger.log("Attribution already sent, returning cached result", level: .debug)
                return cached
            }
        }

        // Get attribution token from AdServices (with retry for transient errors)
        let token = try await getAttributionToken()

        // Build request with device info
        let info = DeviceInfo(
            osVersion: osVersion,
            model: deviceModel,
            locale: Locale.current.identifier
        )
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let request = AttributionRequest(
            attributionToken: token,
            bundleId: bundleId,
            appVersion: appVersion,
            sdkVersion: SpendOwl.sdkVersion,
            userId: userId,
            deviceInfo: info
        )

        // Defensively persist the payload before the first send so a backgrounding
        // mid-request doesn't lose the install. Cleared on success.
        queue.save(PendingAttribution(
            attributionToken: token,
            bundleId: bundleId,
            appVersion: appVersion,
            sdkVersion: SpendOwl.sdkVersion,
            userId: userId,
            osVersion: info.osVersion,
            deviceModel: info.model,
            locale: info.locale,
            createdAt: Date()
        ))

        do {
            let result = try await sender(request)
            applySuccess(result)
            return result
        } catch {
            // Keep the pending payload so the next launch can replay it.
            Logger.log("Attribution send failed, will retry on next launch: \(error)", level: .info)
            throw error
        }
    }

    // MARK: - Private Methods

    private func getAttributionToken() async throws -> String {
        guard #available(iOS 14.3, *) else {
            throw SpendOwlError.attributionUnavailable
        }

        var lastError: Error?
        let totalAttempts = retryDelays.count + 1

        for attempt in 0 ..< totalAttempts {
            do {
                let token = try tokenProvider()
                if attempt > 0 {
                    Logger.log("Got attribution token after \(attempt + 1) attempts", level: .debug)
                } else {
                    Logger.log("Got attribution token", level: .debug)
                }
                return token
            } catch {
                lastError = error
                let nsError = error as NSError

                // Code 3 (PlatformNotSupported) is permanent — retrying won't help.
                if nsError.domain == "AAAttributionErrorDomain", nsError.code == 3 {
                    Logger.log("AdServices reports platform not supported", level: .debug)
                    throw SpendOwlError.attributionUnavailable
                }

                Logger.log(
                    "Attribution token attempt \(attempt + 1)/\(totalAttempts) failed: \(error)",
                    level: .debug
                )

                // Sleep before the next attempt, except after the final one.
                // Cancellation propagates so the loop aborts cleanly when the
                // parent Task is cancelled (e.g. SDK shutdown).
                if attempt < retryDelays.count {
                    let delay = retryDelays[attempt]
                    try await sleep(UInt64(delay * 1_000_000_000))
                }
            }
        }

        Logger.log("Attribution token unavailable after \(totalAttempts) attempts", level: .error)
        return try mapTokenError(lastError)
    }

    private func mapTokenError(_ error: Error?) throws -> String {
        guard let error else {
            throw SpendOwlError.attributionUnavailable
        }
        let nsError = error as NSError
        if nsError.domain == "AAAttributionErrorDomain" {
            switch nsError.code {
            case 1: // AAAttributionErrorCodeNetworkError
                throw SpendOwlError.networkError(error)
            case 2: // AAAttributionErrorCodeInternalError
                throw SpendOwlError.attributionUnavailable
            case 3: // AAAttributionErrorCodePlatformNotSupported (also handled inline)
                throw SpendOwlError.attributionUnavailable
            default:
                throw SpendOwlError.attributionDenied
            }
        }
        throw SpendOwlError.attributionUnavailable
    }

    /// Replays a previously persisted attribution payload, if one exists.
    ///
    /// - Returns: The result from the backend on a successful replay, or `nil`
    ///   if there was no pending payload or the replay failed.
    private func replayPendingIfNeeded() async -> AttributionResult? {
        guard let pending = queue.load() else { return nil }

        let request = AttributionRequest(
            attributionToken: pending.attributionToken,
            bundleId: pending.bundleId,
            appVersion: pending.appVersion,
            sdkVersion: pending.sdkVersion,
            userId: pending.userId,
            deviceInfo: DeviceInfo(
                osVersion: pending.osVersion,
                model: pending.deviceModel,
                locale: pending.locale
            )
        )

        do {
            let result = try await sender(request)
            applySuccess(result)
            Logger.log(
                "Replayed pending attribution: \(result.status.rawValue)",
                level: .info
            )
            return result
        } catch {
            Logger.log("Pending attribution replay failed, will try again later: \(error)", level: .info)
            return nil
        }
    }

    private func applySuccess(_ result: AttributionResult) {
        defaults.attributionSent = true
        defaults.attributionStatus = result.status.rawValue
        saveCachedResult(result)
        queue.clear()
        Logger.log("Attribution fetched: \(result.status.rawValue)", level: .info)
    }

    // MARK: - Cache

    private func loadCachedResult() -> AttributionResult? {
        guard let data = defaults.cachedAttributionResult else { return nil }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AttributionResult.self, from: data)
        } catch {
            Logger.log("Failed to decode cached attribution: \(error)", level: .error)
            return nil
        }
    }

    private func saveCachedResult(_ result: AttributionResult) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            defaults.cachedAttributionResult = try encoder.encode(result)
        } catch {
            Logger.log("Failed to encode attribution result: \(error)", level: .error)
        }
    }

    // MARK: - Device Info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let capacity = MemoryLayout.size(ofValue: systemInfo.machine)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }
}
