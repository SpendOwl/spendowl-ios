# Changelog

All notable changes to the SpendOwl iOS SDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.2] - 2026-08-13

### Fixed

- `SpendOwlConfiguration` no longer accepts a `maxRetries` that cannot describe a real
  request. `0` left the SDK unable to send anything while reporting a network failure that
  had never been attempted, and a negative value crashed the host app outright with
  `Range requires lowerBound <= upperBound`. Values below `1` are now raised to `1`.
  ([#16](https://github.com/SpendOwl/spendowl-ios/pull/16))

  This is a behaviour change for anyone who was passing such a value: requests that used to
  be silently dropped are now sent once. Nothing changes for valid configurations.

### Changed

- `maxRetries` is documented as what it is — the **total** number of attempts including the
  first, so the default of `3` means one request plus two retries. The name and behaviour
  were always this way; only the doc comments were wrong. The parameter is not renamed,
  because it is a public initialiser label and renaming it would break every integration
  that passes it. ([#16](https://github.com/SpendOwl/spendowl-ios/pull/16))

## [1.4.1] - 2026-08-13

### Added

- Attribution and purchase-event payloads now carry `consumableHistoryEnabled`, reporting
  whether the host app declares `SKIncludeConsumableInAppPurchaseHistory` in its
  `Info.plist`. Until now the only signal was a console warning, which is off by default
  and compiled out of release builds, so a missing opt-in stayed invisible outside the
  developer's own machine. Nothing changes for the app: no public API, no new call, one
  boolean on requests that were already being sent.
  ([#14](https://github.com/SpendOwl/spendowl-ios/pull/14))

  The flag is on both payloads by design. Attribution is sent once per install, so on its
  own it would freeze at whatever was true on first launch; purchase events flow
  continuously and keep the value current for an app that adds the key in a later version.
  It reports the app's declared intent only — the behaviour it unlocks also requires
  iOS 18 or later at runtime.

## [1.4.0] - 2026-08-13

Consumable purchase coverage is now stated accurately, and apps selling consumables
have a way to close the gap. The public API is unchanged; this is a minor release
because integration gains a step for those apps.

### Added

- `SKIncludeConsumableInAppPurchaseHistory` support. Apps selling consumables should
  set this key to `true` in their own `Info.plist`. On iOS 18 and later it keeps
  finished consumables in `Transaction.all`, which is what the SDK's startup scan
  reads — so the existing recovery path begins covering consumables with no code
  change. The SDK reads the key at launch and logs a warning when it is absent, since
  it cannot set the key itself: Swift package resources never merge into the app's
  `Info.plist`, and StoreKit reads it from the app bundle.
  ([#10](https://github.com/SpendOwl/spendowl-ios/pull/10))

### Fixed

- The 1000-entry cap on confirmed-sent transaction IDs evicted arbitrary entries
  rather than the oldest, because the IDs were held in a `Set` and `Set.first(where:)`
  returns hash order. An ID recorded moments earlier could be dropped while one from
  years back survived. Evicted IDs stop being deduplicated, so their transactions are
  re-sent and have their attribution re-resolved; taking the oldest first confines that
  to transactions least likely to still be visible.
  ([#11](https://github.com/SpendOwl/spendowl-ios/pull/11))

### Changed

- Documentation of what the startup scan recovers was wrong and is corrected. It
  claimed `Transaction.all` was a safety net "including consumables"; StoreKit in fact
  drops a consumable from that history as soon as the app calls `finish()` on it, and
  `Transaction.updates` never carries the result of a direct `Product.purchase()` call.
  Subscriptions and non-consumables were always recovered and still are.
  ([#10](https://github.com/SpendOwl/spendowl-ios/pull/10))
- `Defaults.sentTransactionIds` is an ordered `[String]` rather than a `Set<String>`.
  The persisted representation is unchanged — it was always a string array — so no
  migration is required. ([#11](https://github.com/SpendOwl/spendowl-ios/pull/11))

## [1.3.1] - 2026-08-13

Reliability fixes for the purchase reporting path. No public API changes.

### Fixed

- Purchase events enqueued while a send was in flight could be deleted without ever
  being sent. The queue was trimmed by position after the network call returned, but
  overflow trims from the front, so a full queue plus a concurrent purchase meant the
  removal discarded events the send never carried. Those events could not be
  re-enqueued for the rest of the session, which for consumables — absent from
  `Transaction.all` once finished — meant permanent loss. Removal is now
  identity-based. ([#6](https://github.com/SpendOwl/spendowl-ios/pull/6))
- StoreKit 1 purchase events reported `originalTransactionId` as `nil`, leaving every
  event captured by `SKPaymentTransactionObserver` outside the backend's transaction
  lineage matching. It is now read from `SKPaymentTransaction.original`, falling back
  to the transaction's own identifier on an initial purchase so the payload matches
  StoreKit 2's `Transaction.originalID`.
  ([#7](https://github.com/SpendOwl/spendowl-ios/pull/7))
- `stopObserving()` left transaction IDs that had been claimed but never confirmed
  sent in the in-memory dedup set, so a stop/start within the same process could not
  re-enqueue a transaction the bounded queue had already evicted. The set is now
  re-seeded from the persisted queue. ([#7](https://github.com/SpendOwl/spendowl-ios/pull/7))
- Purchase event sends are now covered by a background-task assertion, the same
  protection the first-launch attribution send already had. A purchase is when the
  user is most likely to background the app, which suspended the process and deferred
  the event to the next launch. ([#8](https://github.com/SpendOwl/spendowl-ios/pull/8))

### Changed

- `.restored`, `.purchasing`, `.deferred` and `.failed` StoreKit 1 transaction states
  are now documented as deliberately unhandled rather than silently skipped. Behaviour
  is unchanged. ([#7](https://github.com/SpendOwl/spendowl-ios/pull/7))

## [1.3.0] - 2026-06-30

### Changed

- Attribution↔purchase linkage always keys off the SDK's stable, device-scoped
  anonymous SpendOwl ID, independent of `setUserId`. Previously the event `userId` was
  `developerId ?? anonymousId`, so an app calling `setUserId` only after login recorded
  attribution under one identity and purchases under another, and the two never
  matched. ([#5](https://github.com/SpendOwl/spendowl-ios/pull/5))

### Added

- `externalUserId`, sent alongside attribution and purchase events. The identifier
  passed to `setUserId` now travels in this field as reporting and lookup metadata
  only — never as the linkage key. The public API is unchanged.
  ([#5](https://github.com/SpendOwl/spendowl-ios/pull/5))

## [1.2.1] - 2026-06-08

### Fixed

- The startup recovery scan used `Transaction.currentEntitlements`, which excludes
  consumables by design, so a consumable missed by the live listeners was never
  recovered. It now scans `Transaction.all`.
  ([#4](https://github.com/SpendOwl/spendowl-ios/pull/4))

## [1.2.0] - 2026-05-06

### Fixed

- First-launch attribution is hardened against transient errors: the AdServices token
  fetch is retried with backoff, and the payload is persisted before the first send so
  a backgrounded or killed app replays it on the next launch instead of losing the
  install. ([#2](https://github.com/SpendOwl/spendowl-ios/pull/2))

## [1.1.0] - 2026-02-23

### Changed

- Purchase tracking is fully automatic through three complementary listeners
  (`SKPaymentTransactionObserver`, `Transaction.updates`, and a startup scan). The
  explicit `trackPurchase()` call is no longer required — `SpendOwl.configure(apiKey:)`
  is enough. ([#1](https://github.com/SpendOwl/spendowl-ios/pull/1))
- "Apple Search Ads" renamed to "Apple Ads" throughout, and README badge URLs
  corrected.

## [1.0.0] - 2026-02-18

Initial release: Apple Ads attribution and StoreKit 2 purchase tracking.

[1.4.2]: https://github.com/SpendOwl/spendowl-ios/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/SpendOwl/spendowl-ios/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/SpendOwl/spendowl-ios/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/SpendOwl/spendowl-ios/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/SpendOwl/spendowl-ios/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/SpendOwl/spendowl-ios/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/SpendOwl/spendowl-ios/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/SpendOwl/spendowl-ios/compare/1.0.0...v1.1.0
[1.0.0]: https://github.com/SpendOwl/spendowl-ios/releases/tag/1.0.0
