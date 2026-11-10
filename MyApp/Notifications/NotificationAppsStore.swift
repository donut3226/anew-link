import Foundation
import Observation

/// Which iPhone apps reach the band, with what LED colour and vibration (spec 15.3).
///
/// iOS delivers the notifications themselves through ANCS; this list only tells the band which
/// apps to show and how. The band can't be read back, so the app's list is the source of truth:
/// every change (a user action) sends the whole list. If the band isn't connected, the change
/// waits and is sent on the next connection.
@Observable
final class NotificationAppsStore {

    private static let listKey = "notificationApps.list"
    private static let pendingKey = "notificationApps.pending"
    private static let sentKey = "notificationApps.everSent"

    enum Status: Equatable {
        case idle
        case sending
        case sent(at: Date)
        /// Saved on the phone; sent when the band connects.
        case waiting
        case failed(String)
    }

    private(set) var apps: [NotifyApp] = WenaNotificationList.defaultList()
    private(set) var status: Status = .idle

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var pending: Bool {
        get { defaults.bool(forKey: Self.pendingKey) }
        set { defaults.set(newValue, forKey: Self.pendingKey) }
    }

    init() {
        if let data = defaults.data(forKey: Self.listKey),
           let saved = try? JSONDecoder().decode([NotifyApp].self, from: data) {
            apps = WenaNotificationList.ordered(saved)
        }
        if pending { status = .waiting }
    }

    /// True until the list has been sent once (so the screen can say the band still has its old list).
    var neverSent: Bool { !defaults.bool(forKey: Self.sentKey) }

    /// Saves the new list and sends it.
    func update(_ list: [NotifyApp], using connection: BandConnection) async {
        let ordered = WenaNotificationList.ordered(list)
        guard ordered != apps else { return }
        apps = ordered
        if let data = try? JSONEncoder().encode(apps) {
            defaults.set(data, forKey: Self.listKey)
        }
        pending = true
        _ = await send(using: connection)
    }

    /// Sends the list as it is, for "Send all settings".
    func sendAll(using connection: BandConnection) async {
        pending = true
        _ = await send(using: connection)
    }

    /// Called when the band connects. Returns a line for the log, or nil if nothing was waiting.
    func sendIfPending(using connection: BandConnection) async -> String? {
        guard pending else { return nil }
        return await send(using: connection) ? "Sent waiting notification list" : nil
    }

    private func send(using connection: BandConnection) async -> Bool {
        guard connection.state == .connected, !connection.isSending, !connection.activity.inProgress else {
            status = .waiting
            return false
        }
        status = .sending
        if let error = await connection.sendNotificationList(WenaNotificationList.packets(for: apps)) {
            status = .failed(error)
            return false
        }
        pending = false
        defaults.set(true, forKey: Self.sentKey)
        status = .sent(at: Date())
        return true
    }
}
