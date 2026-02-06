//
//  AttributionService.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import AdServices
import Foundation

/// Internal service for retrieving Apple Search Ads attribution.
///
/// Uses Apple's AdServices framework to obtain an attribution token,
/// which is sent to SpendOwl's backend for processing. The backend
/// calls Apple's API to retrieve the full attribution data.
@available(iOS 15.0, macOS 12.0, *)
final class AttributionService: @unchecked Sendable {
    // MARK: - Properties

    private let apiClient: APIClient
    private let defaults = Defaults.shared

    // MARK: - Initialization

    init(apiClient: APIClient) {
        self.apiClient = apiClient
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
        // Return cached result if already sent (unless forced)
        if !forceRefresh, defaults.attributionSent {
            if let cached = loadCachedResult() {
                Logger.log("Attribution already sent, returning cached result", level: .debug)
                return cached
            }
        }

        // Get attribution token from AdServices
        let token = try await getAttributionToken()

        // Build request with device info
        let request = AttributionRequest(
            attributionToken: token,
            bundleId: Bundle.main.bundleIdentifier ?? "unknown",
            appVersion: appVersion,
            sdkVersion: SpendOwl.sdkVersion,
            userId: userId,
            deviceInfo: DeviceInfo(
                osVersion: osVersion,
                model: deviceModel,
                locale: Locale.current.identifier
            )
        )

        // Send to backend and get full attribution data
        let result = try await apiClient.sendAttribution(request)

        // Cache the full result
        defaults.attributionSent = true
        defaults.attributionStatus = result.status.rawValue
        saveCachedResult(result)

        Logger.log("Attribution fetched: \(result.status.rawValue)", level: .info)

        return result
    }

    // MARK: - Private Methods

    private func getAttributionToken() async throws -> String {
        guard #available(iOS 14.3, *) else {
            throw SpendOwlError.attributionUnavailable
        }

        do {
            let token = try AAAttribution.attributionToken()
            Logger.log("Got attribution token", level: .debug)
            return token
        } catch {
            Logger.log("Failed to get attribution token: \(error)", level: .error)

            // Map AdServices errors to SpendOwlError
            let nsError = error as NSError
            if nsError.domain == "AAAttributionErrorDomain" {
                switch nsError.code {
                case 1: // AAAttributionErrorCodeNetworkError
                    throw SpendOwlError.networkError(error)
                case 2: // AAAttributionErrorCodeInternalError
                    throw SpendOwlError.attributionUnavailable
                case 3: // AAAttributionErrorCodePlatformNotSupported
                    throw SpendOwlError.attributionUnavailable
                default:
                    throw SpendOwlError.attributionDenied
                }
            }

            throw SpendOwlError.attributionUnavailable
        }
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
