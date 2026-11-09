import SwiftUI
import UIKit

/// The app icon choices. `iconName` is the name of an alternate icon set in Assets.xcassets
/// (listed in the ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES build setting); nil means the main icon.
nonisolated enum AppIconChoice: String, CaseIterable, Identifiable {
    /// The main icon: Sunrise normally, Night when the home screen is set to Dark.
    case automatic
    case sunrise
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .sunrise: "Sunrise"
        case .night: "Night"
        }
    }

    var iconName: String? {
        switch self {
        case .automatic: nil
        case .sunrise: "AppIcon-Sunrise"
        case .night: "AppIcon-Night"
        }
    }

    /// The choice that matches the icon iOS is using now (an unknown name counts as Automatic).
    init(iconName: String?) {
        self = Self.allCases.first { $0.iconName == iconName } ?? .automatic
    }
}

/// "App icon" settings section. iOS itself shows a short "You have changed the icon" message.
struct AppIconSection: View {
    @State private var choice = AppIconChoice(iconName: UIApplication.shared.alternateIconName)
    @State private var failure: String?

    var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            Section {
                Picker("App icon", selection: $choice) {
                    ForEach(AppIconChoice.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("App icon")
            } footer: {
                Text("Automatic shows Sunrise, and Night when your home screen is set to Dark.")
            }
            .onChange(of: choice) { _, newChoice in
                Task { await apply(newChoice) }
            }
        }
    }

    private func apply(_ newChoice: AppIconChoice) async {
        let app = UIApplication.shared
        guard app.alternateIconName != newChoice.iconName else { return }
        do {
            try await app.setAlternateIconName(newChoice.iconName)
            failure = nil
        } catch {
            failure = "Couldn't change the icon. \(error.localizedDescription)"
            choice = AppIconChoice(iconName: app.alternateIconName)
        }
    }
}
