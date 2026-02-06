import SwiftUI
import SpendOwl

@main
struct SpendOwlDemoApp: App {
    init() {
        // Enable logging for demo
        SpendOwl.enableLogging = true

        // Configure with your API key
        // Get your API key from https://spendowl.io/dashboard
        SpendOwl.configure(apiKey: "demo-api-key")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
