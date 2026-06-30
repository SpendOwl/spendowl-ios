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

    /// The maximum number of retry attempts for failed requests.
    ///
    /// Defaults to 3. Failed requests are retried with exponential backoff.
    /// Client errors (4xx) are not retried.
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
    ///   - maxRetries: Maximum retry attempts for failed requests. Defaults to 3.
    public init(
        apiKey: String,
        baseURL: URL = Self.defaultBaseURL,
        timeoutInterval: TimeInterval = 10,
        maxRetries: Int = 3
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        self.maxRetries = maxRetries
    }
}
