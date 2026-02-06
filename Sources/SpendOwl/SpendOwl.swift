//
//  SpendOwl.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation

/// The main entry point for the SpendOwl SDK.
///
/// SpendOwl provides Apple Search Ads attribution and purchase tracking for iOS apps,
/// enabling accurate ROAS (Return on Ad Spend) measurement.
///
/// ## Overview
///
/// SpendOwl uses a backend-driven architecture where attribution tokens are sent to
/// SpendOwl servers for processing. This approach ensures your app continues working
/// even when Apple changes their APIs.
///
/// ## Getting Started
///
/// Configure the SDK once during app launch:
///
/// ```swift
/// import SpendOwl
///
/// @main
/// struct MyApp: App {
///     init() {
///         SpendOwl.configure(apiKey: "your-api-key")
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///     }
/// }
/// ```
///
/// ## User Identity
///
/// Associate attribution and purchases with your user accounts:
///
/// ```swift
/// // After login
/// SpendOwl.setUserId("user-123")
///
/// // On logout
/// SpendOwl.clearUserId()
/// ```
///
/// ## Attribution Data
///
/// Access attribution data to understand where users came from:
///
/// ```swift
/// Task {
///     do {
///         let attribution = try await SpendOwl.attribution()
///         print("Campaign: \(attribution.campaignName ?? "organic")")
///     } catch {
///         print("Attribution error: \(error)")
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Configuration
/// - ``configure(apiKey:)``
/// - ``configure(_:)``
/// - ``SpendOwlConfiguration``
///
/// ### User Identity
/// - ``setUserId(_:)``
/// - ``clearUserId()``
///
/// ### Attribution
/// - ``attribution()``
/// - ``attribution(completion:)``
/// - ``AttributionResult``
/// - ``AttributionStatus``
///
/// ### Debugging
/// - ``enableLogging``
/// - ``logLevel``
/// - ``isConfigured``
///
@available(iOS 15.0, macOS 12.0, *)
public final class SpendOwl: @unchecked Sendable {
    // MARK: - Singleton

    /// The shared SpendOwl instance.
    ///
    /// You don't need to access this directly. Use the static methods instead.
    public static let shared = SpendOwl()

    // MARK: - Public Properties

    /// Enables or disables debug logging.
    ///
    /// When enabled, SpendOwl logs attribution and purchase events to the Xcode console.
    /// Only active in DEBUG builds.
    ///
    /// ```swift
    /// SpendOwl.enableLogging = true
    /// ```
    ///
    /// - Note: Logging is disabled by default. Enable only during development.
    public static var enableLogging: Bool {
        get { Logger.level != .none }
        set { Logger.level = newValue ? .debug : .none }
    }

    /// The current log level for more granular control.
    ///
    /// Available levels:
    /// - `.none`: No logging (default)
    /// - `.error`: Only errors
    /// - `.info`: Errors and important events
    /// - `.debug`: All messages including debug info
    ///
    /// ```swift
    /// SpendOwl.logLevel = .debug
    /// ```
    public static var logLevel: Logger.Level {
        get { Logger.level }
        set { Logger.level = newValue }
    }

    // MARK: - Private Properties

    private var configuration: SpendOwlConfiguration?
    private var apiClient: APIClient?
    private var attributionService: AttributionService?
    private var purchaseTracker: PurchaseTracker?
    private var userId: String?

    private let lock = NSLock()

    private init() {}

    // MARK: - Configuration

    /// Configures the SpendOwl SDK with your API key.
    ///
    /// Call this method once during app launch, typically in your `App.init()` or
    /// `application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// ```swift
    /// SpendOwl.configure(apiKey: "spendowl_live_xxx")
    /// ```
    ///
    /// After configuration:
    /// - Attribution is automatically tracked
    /// - StoreKit 2 purchases are automatically observed
    /// - Both are required for accurate ROAS calculation
    ///
    /// - Parameter apiKey: Your SpendOwl API key from the dashboard.
    /// - Important: Call this method only once. Subsequent calls are ignored.
    public static func configure(apiKey: String) {
        configure(SpendOwlConfiguration(apiKey: apiKey))
    }

    /// Configures the SpendOwl SDK with custom options.
    ///
    /// Use this method when you need to customize network settings:
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
    /// - Parameter configuration: The configuration options.
    /// - Important: Call this method only once. Subsequent calls are ignored.
    public static func configure(_ configuration: SpendOwlConfiguration) {
        shared.lock.lock()
        defer { shared.lock.unlock() }

        guard shared.configuration == nil else {
            Logger.log("SpendOwl already configured, ignoring", level: .info)
            return
        }

        shared.configuration = configuration
        let client = APIClient(configuration: configuration)
        shared.apiClient = client
        shared.attributionService = AttributionService(apiClient: client)
        shared.purchaseTracker = PurchaseTracker(apiClient: client)

        Logger.log(
            "SpendOwl SDK v\(Self.sdkVersion) configured (key: \(APIClient.sanitizedKey(configuration.apiKey)))",
            level: .info
        )

        // Always track attribution for ROAS calculation
        Task {
            await shared.trackAttributionInternal(completion: nil)
        }

        // Always track purchases for ROAS calculation
        shared.purchaseTracker?.startObserving()
        Logger.log("Purchase tracking started", level: .info)
    }

    // MARK: - User Identity

    /// Sets the user ID for attribution and purchase tracking.
    ///
    /// Call this after the user logs in or registers to associate attribution
    /// and purchases with their account.
    ///
    /// ```swift
    /// // After successful login
    /// SpendOwl.setUserId(user.id)
    /// ```
    ///
    /// - Parameter userId: Your internal user identifier (e.g., database ID, UUID).
    /// - Note: The user ID is included with all subsequent attribution and purchase events.
    public static func setUserId(_ userId: String) {
        shared.lock.lock()
        shared.userId = userId
        shared.purchaseTracker?.setUserId(userId)
        shared.lock.unlock()

        Logger.log("User ID set: \(userId.prefix(8))...", level: .info)
    }

    /// Clears the current user ID.
    ///
    /// Call this when the user logs out to stop associating events with their account.
    ///
    /// ```swift
    /// // On logout
    /// SpendOwl.clearUserId()
    /// ```
    public static func clearUserId() {
        shared.lock.lock()
        shared.userId = nil
        shared.purchaseTracker?.setUserId(nil)
        shared.lock.unlock()

        Logger.log("User ID cleared", level: .info)
    }

    // MARK: - Attribution

    /// Fetches attribution data using a completion handler.
    ///
    /// Attribution is automatically fetched when you call `configure()`. Use this
    /// method to manually fetch attribution or to receive the cached result.
    ///
    /// ```swift
    /// SpendOwl.attribution { result in
    ///     switch result {
    ///     case .success(let attribution):
    ///         if attribution.status == .attributed {
    ///             print("Campaign: \(attribution.campaignName ?? "unknown")")
    ///         }
    ///     case .failure(let error):
    ///         print("Error: \(error)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter completion: Called with the attribution result. May be called on any queue.
    public static func attribution(completion: ((Result<AttributionResult, SpendOwlError>) -> Void)? = nil) {
        Task {
            await shared.trackAttributionInternal(completion: completion)
        }
    }

    /// Fetches attribution data asynchronously.
    ///
    /// Attribution is automatically fetched when you call `configure()`. Use this
    /// method to access the cached result or force a refresh.
    ///
    /// ```swift
    /// Task {
    ///     do {
    ///         let attribution = try await SpendOwl.attribution()
    ///         switch attribution.status {
    ///         case .attributed:
    ///             print("From campaign: \(attribution.campaignName ?? "unknown")")
    ///         case .organic:
    ///             print("Organic install")
    ///         case .unknown:
    ///             print("Attribution pending")
    ///         }
    ///     } catch {
    ///         print("Attribution error: \(error)")
    ///     }
    /// }
    /// ```
    ///
    /// - Returns: The attribution result containing campaign, ad group, and keyword data.
    /// - Throws: ``SpendOwlError`` if attribution fails.
    public static func attribution() async throws -> AttributionResult {
        try await shared.attributionInternal()
    }

    // MARK: - Internal

    private func trackAttributionInternal(completion: ((Result<AttributionResult, SpendOwlError>) -> Void)?) async {
        do {
            let result = try await attributionInternal()
            completion?(.success(result))
        } catch let error as SpendOwlError {
            Logger.log("Attribution failed: \(error)", level: .error)
            completion?(.failure(error))
        } catch {
            Logger.log("Attribution failed: \(error)", level: .error)
            completion?(.failure(.unknown(error)))
        }
    }

    private func attributionInternal() async throws -> AttributionResult {
        guard let service = attributionService else {
            throw SpendOwlError.notConfigured
        }

        // Always send a user ID - either developer-set or anonymous
        let effectiveUserId = userId ?? KeychainHelper.shared.getOrCreateAnonymousId()
        return try await service.fetchAttribution(userId: effectiveUserId)
    }
}

// MARK: - Public Properties

@available(iOS 15.0, macOS 12.0, *)
extension SpendOwl {
    /// Returns `true` if the SDK is configured and ready to use.
    ///
    /// ```swift
    /// if SpendOwl.isConfigured {
    ///     // SDK is ready
    /// }
    /// ```
    public static var isConfigured: Bool {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.configuration != nil
    }

    /// The current SDK version.
    public static var sdkVersion: String {
        spendOwlVersion
    }
}
