import SwiftUI
import Playgrounds

struct ContentView: View {
    let services: AppServices

    var body: some View {
        #if DEBUG
        // Debug only: `-demoScreen <name>` opens one screen with demo data, for simulator checks.
        if let screen = UserDefaults.standard.string(forKey: "demoScreen") {
            DemoScreen(name: screen)
        } else {
            BandStatusView(services: services)
        }
        #else
        BandStatusView(services: services)
        #endif
    }
}

#if DEBUG
/// One screen with made-up data and no band, picked by the `-demoScreen` launch argument.
private struct DemoScreen: View {
    let name: String
    @State private var apps = WenaNotificationList.defaultList()
    @State private var settings = BandSettings()

    var body: some View {
        NavigationStack {
            switch name {
            case "notifications":
                NotificationAppsView(apps: apps, status: .sent(at: Date()), onChange: { apps = WenaNotificationList.ordered($0) })
            case "statusPages":
                OrderEditor(title: "Status pages", items: settings.statusOrder, label: \.label) { settings.statusOrder = $0 }
            default:
                BandSettingsView(settings: settings, status: .sent(at: Date()), onChange: { settings = $0 })
            }
        }
    }
}
#endif

#Playground {
    _ = 1 + 2
}
