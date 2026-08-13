//
//  ConsumableHistory.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation

/// Reports whether the host app has opted into keeping finished consumables in
/// StoreKit's transaction history.
///
/// StoreKit drops a consumable from `Transaction.all` as soon as the app calls
/// `finish()` on it, so the SDK's startup scan cannot recover consumables it missed
/// live — and `Transaction.updates` never carries the result of a direct
/// `Product.purchase()` call. Subscriptions and non-consumables are unaffected: they
/// stay in history and any later launch re-emits them.
///
/// From iOS 18 the host app can opt back in by adding this to its **own** `Info.plist`:
///
/// ```xml
/// <key>SKIncludeConsumableInAppPurchaseHistory</key>
/// <true/>
/// ```
///
/// With that set, finished consumables reappear in `Transaction.all` and the existing
/// scan recovers them with no further work.
///
/// The SDK cannot set this itself. A Swift package's resources are bundled separately
/// and never merged into the app's `Info.plist`, and StoreKit reads the key from the
/// main app bundle. So the most the SDK can do is notice it is missing and say so —
/// which is the point of this type: the gap can't be closed from here, but it doesn't
/// have to be silent.
enum ConsumableHistory {
    static let infoPlistKey = "SKIncludeConsumableInAppPurchaseHistory"

    /// `true` when the host app's `Info.plist` opts into finished-consumable history.
    ///
    /// Reads `Bundle.main`, which is the host app rather than the SDK's resource bundle.
    /// Note this reflects the app's declared intent only — the behaviour it unlocks also
    /// requires iOS 18 / macOS 15 at runtime.
    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? Bool ?? false
    }

    /// Logs a one-line warning when the opt-in is missing.
    ///
    /// Deliberately unconditional on OS version and on whether the app actually sells
    /// consumables: the SDK cannot know the product catalogue, and an app on iOS 17
    /// today will be on a newer OS later. Logging is off by default
    /// (``SpendOwl/enableLogging``), so this only ever surfaces for a developer who has
    /// turned it on — which is exactly when it is actionable.
    static func warnIfMissing() {
        guard !isEnabled else {
            Logger.log("Finished consumables are included in transaction history", level: .debug)
            return
        }

        Logger.log(
            """
            \(infoPlistKey) is not set in your Info.plist. Consumable purchases the SDK \
            misses at the moment of purchase cannot be recovered by the startup scan, \
            because StoreKit drops finished consumables from Transaction.all. Set it to \
            true to close that gap on iOS 18 and later. Subscriptions and non-consumables \
            are unaffected.
            """,
            level: .info
        )
    }
}
