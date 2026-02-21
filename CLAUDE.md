# CLAUDE.md - SpendOwl iOS SDK

This file provides guidance for Claude Code when working with the SpendOwl iOS SDK.

## Project Overview

SpendOwl is a lightweight iOS SDK for Apple Ads attribution and StoreKit 2 purchase tracking. It uses a backend-driven architecture where attribution tokens are sent to SpendOwl servers for processing.

## Project Structure

```
spendowl-ios/
├── Sources/SpendOwl/
│   ├── SpendOwl.swift              # Main entry point, public API
│   ├── Configuration.swift          # SDK configuration options
│   ├── SpendOwlError.swift          # Error types
│   ├── Logger.swift                 # Internal logging
│   ├── Version.swift               # SDK version constant
│   ├── Attribution/
│   │   ├── AttributionResult.swift  # Attribution data model
│   │   └── AttributionService.swift # AdServices integration
│   ├── Purchases/
│   │   └── PurchaseTracker.swift    # StoreKit 2 observer
│   ├── Network/
│   │   └── APIClient.swift          # HTTP client
│   └── Storage/
│       ├── Defaults.swift           # UserDefaults wrapper
│       ├── EventQueue.swift         # Persistent event retry queue
│       └── KeychainHelper.swift     # Keychain wrapper
├── Tests/SpendOwlTests/
├── Examples/
│   ├── SpendOwlDemo-SwiftUI/
│   └── SpendOwlDemo-UIKit/
├── .github/workflows/ci.yml        # CI pipeline
├── CONTRIBUTING.md
└── Package.swift
```

## Build & Test Commands

```bash
# Build the package
swift build

# Run tests
swift test

# Lint code (requires SwiftLint)
swiftlint lint --config .swiftlint.yml

# Format code (requires SwiftFormat)
swiftformat Sources Tests --config .swiftformat
```

## Code Style

- Follow Swift API Design Guidelines
- Use `Logger.log()` instead of `print()` for debugging
- All public APIs must have DocC documentation
- Add `@available(iOS 15.0, *)` to types using async/await or StoreKit 2
- Use `Sendable` conformance for thread-safe types

## Key Patterns

### Error Handling

All public APIs are crash-proof. Errors are returned through completion handlers or thrown:

```swift
public static func attribution() async throws -> AttributionResult
public static func attribution(completion: ((Result<AttributionResult, SpendOwlError>) -> Void)?)
```

### Thread Safety

- `SpendOwl` uses `NSLock` for synchronization
- `APIClient` is an `actor` for safe async access
- Storage classes use `@unchecked Sendable` with internal synchronization

### Backend-Driven Architecture

The SDK only calls `AAAttribution.attributionToken()` on device. The token is sent to SpendOwl's backend which calls Apple's AdServices API. This allows backend-only fixes when Apple changes their API.

## Pre-commit Checks

Before committing, ensure:

1. All tests pass: `swift test`
2. No lint warnings: `swiftlint lint`
3. Code is formatted: `swiftformat Sources Tests`

## Making Changes

When modifying public APIs:

1. Update DocC documentation
2. Update README.md if needed
3. Add/update tests
4. Run lint and format checks
