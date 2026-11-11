import SwiftUI
import Playgrounds

struct ContentView: View {
    let services: AppServices

    var body: some View {
        #if DEBUG
        // Debug only: `-demoScreen <name>` opens one screen with demo data, for simulator checks.
        // `-demoBattery <percent>` puts a made-up reading in the widget's shared storage.
        let _ = UserDefaults.standard.object(forKey: "demoBattery").map { BandBatteryShare.save(($0 as? Int) ?? Int("\($0)") ?? 50) }
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
            case "calendars":
                CalendarChoicesView(choices: [
                    CalendarChoice(id: "home", title: "Home", account: "iCloud", isIncluded: true),
                    CalendarChoice(id: "work", title: "Work", account: "iCloud", isIncluded: false),
                ], onToggle: { _, _ in })
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
