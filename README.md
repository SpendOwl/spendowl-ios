<h1 align="center">SpendOwl</h1>

<h3 align="center">Measure True ROAS for Apple Ads</h3>

<p align="center">
  <a href="https://github.com/SpendOwl/spendowl-ios/releases"><img src="https://img.shields.io/github/v/release/SpendOwl/spendowl-ios?style=flat" alt="Release"></a>
  <a href="https://swiftpackageindex.com/SpendOwl/spendowl-ios"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSpendOwl%2Fspendowl-ios%2Fbadge%3Ftype%3Dswift-versions" alt="Swift"></a>
  <a href="https://swiftpackageindex.com/SpendOwl/spendowl-ios"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSpendOwl%2Fspendowl-ios%2Fbadge%3Ftype%3Dplatforms" alt="Platforms"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
</p>

SpendOwl connects your Apple Ads spend to actual revenue. Get campaign, ad group, and keyword-level ROAS in your dashboard.

## Why SpendOwl?

- **Attribution Tracking** — Campaign, ad group, keyword, and placement data from Apple Ads
- **Revenue Tracking** — Automatic StoreKit purchase observation
- **Backend-Driven** — Apple API changes require no SDK updates
- **Works with RevenueCat/Adapty** — No conflicts with other subscription SDKs
- **Privacy-First** — No IDFA required, includes privacy manifest

## Installation

### Swift Package Manager

```
https://github.com/SpendOwl/spendowl-ios
```

## Quick Start

```swift
import SpendOwl

// 1. Configure on app launch
SpendOwl.configure(apiKey: "your-api-key")

// 2. Set your user ID (optional) — attaches your own identifier for reporting
//    and lookups. Safe to call any time (e.g. after login); it does NOT affect
//    how attribution and purchases are linked, so it works even when set late.
SpendOwl.setUserId("user-123")

// 3. That's it! Purchases are tracked automatically.

// 4. Get attribution data (optional)
let attribution = try await SpendOwl.attribution()
print(attribution.campaignName ?? "organic")
```

## Selling consumables?

**Only relevant if your app sells consumable products.** Subscriptions and
non-consumables need nothing beyond the Quick Start above.

Add this to your app's `Info.plist`:

```xml
<key>SKIncludeConsumableInAppPurchaseHistory</key>
<true/>
```

**Why.** StoreKit removes a consumable from `Transaction.all` the moment your app calls
`finish()` on it. SpendOwl re-scans that history on every launch to catch purchases it
missed live, so without this key a missed consumable is missed permanently — while
subscriptions and non-consumables are always recovered. Setting it to `true` keeps
finished consumables in history on iOS 18 and later, and SpendOwl picks them up with no
further work from you.

There is no code to call — this is a one-time project setting. SpendOwl cannot add the
key for you: Swift packages cannot contribute entries to your app's `Info.plist`, and
StoreKit reads it from the app bundle. Enable `SpendOwl.enableLogging` during
integration and the SDK will tell you if the key is missing.

**On iOS 17 and earlier** this is not possible at all — Apple provides no way to see a
finished consumable, so a consumable that isn't captured at the moment of purchase
cannot be recovered. SpendOwl does not ship a manual reporting API to work around it.
As of mid-2026 iOS 18+ covers roughly 97% of devices, and that share keeps growing.

## Requirements

| | Minimum |
|---|---|
| iOS | 15.0 |
| Xcode | 15.0 |
| Swift | 5.9 |

## Documentation

Full documentation available at **[docs.spendowl.io](https://docs.spendowl.io)**

## Example Apps

- [SwiftUI Example](Examples/SpendOwlDemo-SwiftUI)
- [UIKit Example](Examples/SpendOwlDemo-UIKit)

## License

MIT. See [LICENSE](LICENSE).
