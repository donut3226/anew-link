import SwiftUI
import UIKit

@main struct MyApp: App {
    /// Connects an old-style "app delegate" to this SwiftUI app. iOS tells the delegate when
    /// the app launches, including a background relaunch for the band with no screen shown.
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(services: appDelegate.services)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    let services = AppServices()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Start Bluetooth straight away, so a restored connection is picked up even in the background.
        services.start()
        return true
    }
}
