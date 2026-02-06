# SpendOwl Demo (SwiftUI)

A SwiftUI sample app demonstrating SpendOwl SDK integration.

## Features

- **Attribution Tracking** - Fetch and display Apple Search Ads attribution data
- **User Identity** - Set and clear user IDs
- **Purchase Tracking** - Automatic StoreKit 2 purchase tracking
- **Debug Controls** - Toggle logging and view SDK status

## Running the Demo

1. Open `Examples/SpendOwlDemo-SwiftUI` folder in Xcode
2. Select an iOS simulator (iPhone 15 or later recommended)
3. Build and run (⌘R)

> **Note:** This is an iOS-only app. Use Xcode to build and run on simulator or device.

## Configuration

Replace `demo-api-key` in `SpendOwlDemoApp.swift` with your actual API key:

```swift
SpendOwl.configure(apiKey: "your-actual-api-key")
```

Get your API key from [SpendOwl Dashboard](https://spendowl.io/dashboard).

## Project Structure

```
SpendOwlDemo-SwiftUI/
├── SpendOwlDemoApp.swift    # App entry point, SDK configuration
└── ContentView.swift        # Main UI with List sections
```

## Requirements

- iOS 15.0+
- Xcode 15.0+

## Notes

- Attribution requires iOS 14.3+ and AdServices framework
- StoreKit 2 purchase tracking requires iOS 15.0+
- Demo uses mock API key - replace with real key for production testing
- On simulator, attribution will return `.attributionUnavailable` (AdServices requires real device)
