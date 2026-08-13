//
//  BackgroundTaskAssertion.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
#if canImport(UIKit) && os(iOS)
    import UIKit
#endif

// Wraps `UIApplication.beginBackgroundTask(...)` so a short-running async task
// can ask the OS for a few extra seconds before it is suspended.
//
// Used around the two sends that race the app being backgrounded:
//
// 1. The first-launch attribution send, so the request has a chance to complete
//    even if the user backgrounds the app within seconds of `SpendOwl.configure()`.
// 2. Purchase event sends, because the moment right after a purchase completes is
//    when the user is most likely to leave the app.
//
// The expiration handler ends the task immediately to avoid the OS terminating
// the app, and the explicit `end()` is idempotent so it is safe to call from
// the completion path even if the OS already expired us.
//
// On non-iOS platforms (macOS, etc.) this is a no-op.
#if canImport(UIKit) && os(iOS)
    @MainActor
    final class BackgroundTaskAssertion {
        private var identifier: UIBackgroundTaskIdentifier = .invalid

        private init() {}

        static func begin(name: String) -> BackgroundTaskAssertion {
            let assertion = BackgroundTaskAssertion()
            assertion.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak assertion] in
                Logger.log("Background task '\(name)' expired before completion", level: .info)
                assertion?.end()
            }
            return assertion
        }

        func end() {
            guard identifier != .invalid else { return }
            let id = identifier
            identifier = .invalid
            UIApplication.shared.endBackgroundTask(id)
        }
    }
#else
    final class BackgroundTaskAssertion: Sendable {
        private init() {}

        static func begin(name _: String) async -> BackgroundTaskAssertion {
            BackgroundTaskAssertion()
        }

        func end() async {}
    }
#endif
