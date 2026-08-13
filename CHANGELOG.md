# Changelog

All notable changes to the SpendOwl iOS SDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.3.1]: https://github.com/SpendOwl/spendowl-ios/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/SpendOwl/spendowl-ios/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/SpendOwl/spendowl-ios/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/SpendOwl/spendowl-ios/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/SpendOwl/spendowl-ios/compare/1.0.0...v1.1.0
[1.0.0]: https://github.com/SpendOwl/spendowl-ios/releases/tag/1.0.0
