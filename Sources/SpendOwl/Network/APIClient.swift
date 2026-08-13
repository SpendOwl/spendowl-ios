//
//  APIClient.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation

/// Internal network client for SpendOwl API communication.
///
/// Handles all HTTP requests to the SpendOwl backend with automatic retry,
/// exponential backoff, and proper error handling.
@available(iOS 15.0, macOS 12.0, *)
actor APIClient {
    // MARK: - Properties

    private let configuration: SpendOwlConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Initialization

    init(configuration: SpendOwlConfiguration) {
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeoutInterval
        sessionConfig.timeoutIntervalForResource = configuration.timeoutInterval * 2
        session = URLSession(configuration: sessionConfig)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public API

    /// Sends an attribution request to the SpendOwl backend.
    ///
    /// - Parameter request: The attribution request containing the Apple token.
    /// - Returns: The attribution result from the backend.
    /// - Throws: `SpendOwlError` if the request fails.
    func sendAttribution(_ request: AttributionRequest) async throws -> AttributionResult {
        try await post("/v1/attributions", body: request)
    }

    /// Sends purchase events to the SpendOwl backend.
    ///
    /// - Parameter request: The events request containing purchase data.
    /// - Returns: The response indicating how many events were processed.
    /// - Throws: `SpendOwlError` if the request fails.
    func sendEvents(_ request: EventsRequest) async throws -> EventsResponse {
        try await post("/v1/events", body: request)
    }

    // MARK: - Request Execution

    private func post<R: Decodable>(_ path: String, body: some Encodable) async throws -> R {
        let url = configuration.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.bearerToken(configuration.apiKey), forHTTPHeaderField: "Authorization")
        request.setValue("ios/\(SpendOwl.sdkVersion)", forHTTPHeaderField: "X-SpendOwl-SDK")

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw SpendOwlError.encodingError
        }

        return try await executeWithRetry(request)
    }

    /// Sends the request, retrying transient failures with exponential backoff.
    ///
    /// `maxRetries` is a total attempt count, not a retry count — see
    /// ``SpendOwlConfiguration/maxRetries``, which clamps it to at least 1.
    ///
    /// `repeat`/`while` rather than a range loop, so one attempt always happens and
    /// `lastError` can only be thrown after a real failure assigned it. The previous
    /// version iterated `0 ..< maxRetries` over a seeded `URLError(.unknown)`: a
    /// configuration of `0` sent nothing and reported a network failure that had never been
    /// attempted, and a negative value trapped on the range itself.
    private func executeWithRetry<R: Decodable>(_ request: URLRequest) async throws -> R {
        let attempts = configuration.maxRetries
        var attempt = 0
        var lastError: Error

        repeat {
            do {
                return try await execute(request)
            } catch {
                lastError = error

                // Don't retry client errors (4xx)
                if case let SpendOwlError.serverError(code, _) = error, (400 ..< 500).contains(code) {
                    throw error
                }

                // Exponential backoff: 0.5s, 1s, 2s, ...
                if attempt < attempts - 1 {
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    Logger.log("Request failed, retrying in \(delay)s (attempt \(attempt + 1))", level: .debug)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            attempt += 1
        } while attempt < attempts

        throw lastError
    }

    // MARK: - Helpers

    private static func bearerToken(_ apiKey: String) -> String {
        "Bearer \(apiKey)"
    }

    static func sanitizedKey(_ apiKey: String) -> String {
        guard apiKey.count > 8 else { return "***" }
        return String(apiKey.prefix(4)) + "***" + String(apiKey.suffix(4))
    }

    private func execute<R: Decodable>(_ request: URLRequest) async throws -> R {
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SpendOwlError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpendOwlError.networkError(URLError(.badServerResponse))
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw SpendOwlError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw SpendOwlError.decodingError(error)
        }
    }
}

// MARK: - Request Types

/// Request payload for attribution tracking.
struct AttributionRequest: Encodable {
    let attributionToken: String
    let bundleId: String
    let appVersion: String
    let sdkVersion: String
    /// Stable device-scoped linkage identity (the SpendOwl anonymous ID). Always
    /// present — used to join attribution to purchases/revenue server-side.
    let userId: String?
    /// Optional developer-supplied identifier (`SpendOwl.setUserId`). Stored as an
    /// additional attribute for reporting/search; never used as the join key.
    let externalUserId: String?
    let deviceInfo: DeviceInfo
    /// Whether the host app opted into finished-consumable transaction history.
    ///
    /// Reports the app's declared intent so integration health is visible server-side
    /// rather than only in a developer's debug console. Declaring it is not the same as
    /// benefiting from it — the behaviour also needs iOS 18 / macOS 15 at runtime, so read
    /// this alongside `deviceInfo.osVersion`. See ``ConsumableHistory``.
    let consumableHistoryEnabled: Bool
}

/// Device information included with requests.
struct DeviceInfo: Encodable {
    let osVersion: String
    let model: String
    let locale: String
}

/// Request payload for purchase events.
struct EventsRequest: Encodable {
    let events: [PurchaseEvent]
    /// Stable device-scoped linkage identity (the SpendOwl anonymous ID). Always
    /// present — matched server-side to the same user's attribution.
    let userId: String?
    /// Optional developer-supplied identifier (`SpendOwl.setUserId`). Reporting
    /// metadata only; never used to match purchases to attribution.
    let externalUserId: String?
    let bundleId: String
    /// Whether the host app opted into finished-consumable transaction history.
    ///
    /// Carried here as well as on attribution because attribution is only sent once per
    /// install: an app that adds the key in a later version would otherwise keep reporting
    /// the value from its very first launch. Purchase events keep it current.
    let consumableHistoryEnabled: Bool
}

/// A single purchase event.
struct PurchaseEvent: Codable {
    let type: String
    let transactionId: String
    let originalTransactionId: String?
    let productId: String
    let purchaseDate: Date
    let price: String?
    let currency: String?
    let countryCode: String?
    let quantity: Int
    let environment: String
}

// MARK: - Response Types

/// Response from the events endpoint.
struct EventsResponse: Decodable {
    let received: Int
    let processed: Int
}
