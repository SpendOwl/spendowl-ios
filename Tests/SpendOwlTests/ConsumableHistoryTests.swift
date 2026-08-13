//
//  ConsumableHistoryTests.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

@testable import SpendOwl
import XCTest

final class ConsumableHistoryTests: XCTestCase {
    /// The key must match Apple's spelling exactly — a typo here would read as "the host
    /// app never opted in", silently keeping the consumable gap open for apps that did.
    func testInfoPlistKeyMatchesApplesSpelling() {
        XCTAssertEqual(ConsumableHistory.infoPlistKey, "SKIncludeConsumableInAppPurchaseHistory")
    }

    /// The test host has no such key, so this pins the default: absent reads as not
    /// opted in, never as opted in.
    func testMissingKeyReadsAsDisabled() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: ConsumableHistory.infoPlistKey))
        XCTAssertFalse(ConsumableHistory.isEnabled)
    }

    /// Must not trap or throw regardless of the host app's Info.plist — it runs on every
    /// `startObserving()`.
    func testWarnIfMissingIsSafeToCall() {
        ConsumableHistory.warnIfMissing()
    }
}
