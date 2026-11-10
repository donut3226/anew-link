import Foundation
import Observation

/// The band's settings, kept on the iPhone and sent to the band (spec 15).
///
/// The band can't be asked for its settings, so the app's values are the source of truth.
/// Each change is a user action and sends only the packet for that setting, like Sony's app.
/// If the band isn't connected, the change waits and is sent on the next connection.
@Observable
final class BandSettingsStore {

    private static let settingsKey = "bandSettings.values"
    private static let pendingKey = "bandSettings.pending"

    enum Status: Equatable {
        case idle
        case sending
        case sent(at: Date)
        /// Saved on the phone; sent when the band connects.
        case waiting
        case failed(String)
    }

    private(set) var settings = BandSettings()
    private(set) var status: Status = .idle

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Groups changed but not yet on the band (kept across launches).
    @ObservationIgnored private var pending: Set<WenaSettings.Group> {
        get {
            let raw = defaults.stringArray(forKey: Self.pendingKey) ?? []
            return Set(raw.compactMap(WenaSettings.Group.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: Self.pendingKey) }
    }

    init() {
        if let data = defaults.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(BandSettings.self, from: data) {
            settings = saved
        }
        if !pending.isEmpty { status = .waiting }
    }

    /// Saves new values and sends the groups that changed.
    func update(_ new: BandSettings, using connection: BandConnection) async {
        let changed = WenaSettings.Group.allCases.filter {
            WenaSettings.packets(for: $0, new) != WenaSettings.packets(for: $0, settings)
        }
        guard !changed.isEmpty else { return }
        settings = new
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
        pending.formUnion(changed)
        _ = await send(using: connection)
    }

    /// Sends every setting, for example after the band was reset or set up with another app.
    func sendAll(using connection: BandConnection) async {
        pending = Set(WenaSettings.Group.allCases)
        _ = await send(using: connection)
    }

    /// Called when the band connects: sends changes that couldn't be sent earlier.
    /// Returns a line for the log, or nil if nothing was waiting.
    func sendIfPending(using connection: BandConnection) async -> String? {
        guard !pending.isEmpty else { return nil }
        return await send(using: connection) ? "Sent waiting band settings" : nil
    }

    // MARK: - Private

    private func send(using connection: BandConnection) async -> Bool {
        guard connection.state == .connected, !connection.isSending, !connection.activity.inProgress else {
            status = .waiting
            return false
        }
        let groups = pending
        var packets: [Data]
        if groups == Set(WenaSettings.Group.allCases) {
            packets = WenaSettings.allPackets(settings)
        } else {
            // Display is already inside the home icons group, so don't send it twice.
            let order = WenaSettings.Group.allCases.filter { groups.contains($0) }
            let skipDisplay = groups.contains(.homeIcons)
            packets = order.filter { !(skipDisplay && $0 == .display) }
                .flatMap { WenaSettings.packets(for: $0, settings) }
        }
        status = .sending
        if let error = await connection.sendSettings(packets) {
            status = .failed(error)
            return false
        }
        pending.subtract(groups)
        status = pending.isEmpty ? .sent(at: Date()) : .waiting
        return true
    }
}
