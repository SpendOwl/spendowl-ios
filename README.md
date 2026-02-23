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

// 2. Set user ID (optional)
SpendOwl.setUserId("user-123")

// 3. That's it! Purchases are tracked automatically.

// 4. Get attribution data (optional)
let attribution = try await SpendOwl.attribution()
print(attribution.campaignName ?? "organic")
```

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
