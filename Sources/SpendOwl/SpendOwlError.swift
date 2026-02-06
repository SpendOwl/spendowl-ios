//
//  SpendOwlError.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation

/// Errors that can occur within the SpendOwl SDK.
///
/// All SpendOwl operations are crash-proof. When an error occurs, it's returned
/// through the completion handler or thrown from async methods.
///
/// ## Handling Errors
///
/// ```swift
/// SpendOwl.attribution { result in
///     switch result {
///     case .success(let attribution):
///         // Handle attribution
///     case .failure(let error):
///         switch error {
///         case .notConfigured:
///             // SDK not configured yet
///         case .networkError:
///             // Network issue, will be retried automatically
///         case .serverError(let code, let message):
///             // Server error with HTTP status code
///         default:
///             // Other errors
///         }
///     }
/// }
/// ```
public enum SpendOwlError: LocalizedError, Sendable {
    /// The SDK has not been configured.
    ///
    /// Call `SpendOwl.configure(apiKey:)` before using other SDK methods.
    case notConfigured

    /// The provided API key is invalid.
    ///
    /// Check that you're using the correct API key from your SpendOwl dashboard.
    case invalidAPIKey

    /// A network error occurred.
    ///
    /// The SDK automatically retries failed requests with exponential backoff.
    /// This error is returned after all retry attempts have failed.
    case networkError(Error)

    /// The server returned an error response.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - message: An optional error message from the server.
    case serverError(statusCode: Int, message: String?)

    /// Attribution is not available on this device.
    ///
    /// This can occur on iOS versions below 14.3 or when AdServices
    /// framework is not available.
    case attributionUnavailable

    /// Attribution access was denied.
    ///
    /// The user or device has restricted access to attribution data.
    case attributionDenied

    /// Failed to encode request data.
    ///
    /// This is an internal error that should not occur in normal operation.
    case encodingError

    /// Failed to decode the server response.
    ///
    /// This may indicate an API version mismatch. Update to the latest SDK version.
    case decodingError(Error)

    /// An unknown error occurred.
    ///
    /// The underlying error is included for debugging purposes.
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "SpendOwl SDK is not configured. Call SpendOwl.configure(apiKey:) first."
        case .invalidAPIKey:
            "Invalid API key. Check your SpendOwl dashboard for the correct key."
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .serverError(statusCode, message):
            "Server error (\(statusCode)): \(message ?? "Unknown error")"
        case .attributionUnavailable:
            "Attribution is not available on this device or OS version."
        case .attributionDenied:
            "Attribution access was denied."
        case .encodingError:
            "Failed to encode request data."
        case let .decodingError(error):
            "Failed to decode response: \(error.localizedDescription)"
        case let .unknown(error):
            "Unknown error: \(error.localizedDescription)"
        }
    }

    /// A unique error code for programmatic error handling.
    public var errorCode: Int {
        switch self {
        case .notConfigured: 1001
        case .invalidAPIKey: 1002
        case .networkError: 2001
        case .serverError: 2002
        case .attributionUnavailable: 3001
        case .attributionDenied: 3002
        case .encodingError: 4001
        case .decodingError: 4002
        case .unknown: 9999
        }
    }
}

// MARK: - Equatable

extension SpendOwlError: Equatable {
    public static func == (lhs: SpendOwlError, rhs: SpendOwlError) -> Bool {
        lhs.errorCode == rhs.errorCode
    }
}
