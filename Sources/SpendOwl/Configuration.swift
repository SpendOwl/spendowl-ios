//
//  Configuration.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation

/// Configuration options for the SpendOwl SDK.
///
/// Create a configuration to customize network behavior when initializing the SDK:
///
/// ```swift
/// let config = SpendOwlConfiguration(
///     apiKey: "your-api-key",
///     timeoutInterval: 30,
///     maxRetries: 5
/// )
/// SpendOwl.configure(config)
/// ```
///
/// For most use cases, the simple initialization with just an API key is sufficient:
///
/// ```swift
/// SpendOwl.configure(apiKey: "your-api-key")
/// ```
public struct SpendOwlConfiguration: Sendable {
    /// Your SpendOwl API key.
    ///
    /// Get your API key from the [SpendOwl Dashboard](https://spendowl.io/dashboard).
    public let apiKey: String

    /// The base URL for the SpendOwl API.
    ///
    /// Defaults to `https://spendowl.io/api`. Only change this for testing
    /// or if instructed by SpendOwl support.
    public let baseURL: URL

    /// The timeout interval for network requests, in seconds.
    ///
    /// Defaults to 10 seconds. Increase this value if you experience
    /// timeout issues on slow networks.
    public let timeoutInterval: TimeInterval

    /// The total number of attempts made for a request, including the first one.
    ///
    /// Defaults to 3 — one initial request plus two retries — with exponential backoff
    /// between them. Client errors (4xx) are never retried.
    ///
    /// Despite the name this counts attempts rather than retries; a value of `1` means a
    /// single try and no retry at all. Values below `1` are raised to `1`, because a
    /// request count of zero would leave the SDK unable to send anything.
    public let maxRetries: Int

    /// The default API base URL (`https://spendowl.io/api`).
    public static let defaultBaseURL: URL = {
        guard let url = URL(string: "https://spendowl.io/api") else {
            preconditionFailure("Invalid default base URL")
        }
        return url
    }()

    /// Creates a new SpendOwl configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Your SpendOwl API key (required).
    ///   - baseURL: The API base URL. Defaults to SpendOwl production servers.
    ///   - timeoutInterval: Network timeout in seconds. Defaults to 10.
    ///   - maxRetries: Total attempts per request, including the first. Defaults to 3
    ///     (one request plus two retries). Values below 1 are raised to 1.
    public init(
        apiKey: String,
        baseURL: URL = Self.defaultBaseURL,
        timeoutInterval: TimeInterval = 10,
        maxRetries: Int = 3
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        // Clamped here rather than defended at the call site, so no part of the SDK ever
        // sees a value that cannot describe a real request. `0` would stop the SDK sending
        // anything at all, and a negative value used to trap outright — a public
        // initialiser must not be able to crash the host app over a typo.
        self.maxRetries = max(1, maxRetries)
    }
}
