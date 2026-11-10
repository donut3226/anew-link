import AppIntents
import Foundation

/// Shortcuts actions. They run inside the app (in the background when possible), wait for the
/// band to connect, then send one packet. Each run is a user action: the user or their own
/// Shortcuts automation started it.

/// Find my band: makes the band buzz and light up.
struct FindMyBandIntent: AppIntent {
    static let title: LocalizedStringResource = "Find My Band"
    static let description = IntentDescription("Makes your band vibrate and light up, so you can find it.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = try await BandIntentSupport.connectedServices()
        if let error = await services.bandSettings.findBand(using: services.connection) {
            throw BandIntentError.failed(error)
        }
        return .result(dialog: "Your band is buzzing.")
    }
}

/// Focus sync: turn the band's do not disturb on or off, for a Focus automation in Shortcuts
/// (for example "When Sleep turns on, set band do not disturb on").
struct SetBandDoNotDisturbIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Band Do Not Disturb"
    static let description = IntentDescription(
        "Turns do not disturb on the band on (all day) or back to your own setting. Use it in a Focus automation.")

    @Parameter(title: "On", default: true)
    var isOn: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set band do not disturb \(\.$isOn)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = try await BandIntentSupport.connectedServices()
        if let error = await services.bandSettings.setFocusDoNotDisturb(isOn, using: services.connection) {
            throw BandIntentError.failed(error)
        }
        return .result(dialog: isOn ? "Band do not disturb is on." : "Band do not disturb is back to your setting.")
    }
}

struct BandShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FindMyBandIntent(),
                    phrases: ["Find my band with \(.applicationName)", "Buzz my band with \(.applicationName)"],
                    shortTitle: "Find My Band", systemImageName: "waveform")
        AppShortcut(intent: SetBandDoNotDisturbIntent(),
                    phrases: ["Set band do not disturb with \(.applicationName)"],
                    shortTitle: "Band Do Not Disturb", systemImageName: "moon")
    }
}

enum BandIntentError: Error, CustomLocalizedStringResourceConvertible {
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .failed(let message): "\(message)"
        }
    }
}

enum BandIntentSupport {
    /// The app's services once the band is connected, or an error the Shortcut shows.
    static func connectedServices() async throws -> AppServices {
        guard let services = AppServices.shared else {
            throw BandIntentError.failed("Open Anew Link once, then try again.")
        }
        guard await services.connection.waitUntilConnected() else {
            throw BandIntentError.failed("The band isn't connected. Check it's nearby and Bluetooth is on.")
        }
        return services
    }
}
