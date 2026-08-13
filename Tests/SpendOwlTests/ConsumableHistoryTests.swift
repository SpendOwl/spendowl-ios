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

    /// Pins the wire key both request types put the opt-in under.
    ///
    /// `APIClient` encodes without a key strategy (`APIClient.swift:34`), so the Swift
    /// property name *is* the wire name. Renaming the property would compile cleanly and
    /// silently stop feeding the server-side integration health view, which reads this
    /// exact key — the sort of break that only shows up as data quietly going missing.
    ///
    /// Encoding `true` here also proves the field is genuinely carried rather than pinned
    /// to the `false` that the test host's absent key produces everywhere else.
    func testOptInIsEncodedUnderItsExactWireKey() throws {
        let attribution = AttributionRequest(
            attributionToken: "token",
            bundleId: "com.example.app",
            appVersion: "1.0",
            sdkVersion: "1.4.1",
            userId: "anon",
            externalUserId: nil,
            deviceInfo: DeviceInfo(osVersion: "18.0", model: "iPhone", locale: "en_US"),
            consumableHistoryEnabled: true
        )
        let events = EventsRequest(
            events: [],
            userId: "anon",
            externalUserId: nil,
            bundleId: "com.example.app",
            consumableHistoryEnabled: true
        )

        for data in try [JSONEncoder().encode(attribution), JSONEncoder().encode(events)] {
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            XCTAssertEqual(json["consumableHistoryEnabled"] as? Bool, true)
        }
    }
}
