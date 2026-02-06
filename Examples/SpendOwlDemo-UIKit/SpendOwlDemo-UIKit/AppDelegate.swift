import UIKit
import SpendOwl

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Enable logging for demo
        SpendOwl.enableLogging = true

        // Configure SpendOwl SDK
        // Get your API key from https://spendowl.io/dashboard
        SpendOwl.configure(apiKey: "demo-api-key")

        // Setup window
        window = UIWindow(frame: UIScreen.main.bounds)
        let navigationController = UINavigationController(rootViewController: AttributionViewController())
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()

        return true
    }
}
