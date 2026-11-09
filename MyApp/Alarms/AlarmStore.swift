import Foundation
import Observation

/// The band's alarms, kept on the iPhone and sent to the band (spec section 9).
///
/// The band can't be asked for its current alarms, so the app's list is the source of truth:
/// every change (a user action) sends the whole list, which replaces all 9 slots on the band.
/// If the band isn't connected, the change waits and is sent on the next connection.
@Observable
final class AlarmStore {

    private static let alarmsKey = "alarms.list"
    private static let pendingKey = "alarms.pending"

    enum Status: Equatable {
        case idle
        case sending
        case sent(at: Date)
        /// Saved on the phone; sent when the band connects.
        case waiting
        case failed(String)
    }

    private(set) var alarms: [BandAlarm] = []
    private(set) var status: Status = .idle

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// True when a change hasn't reached the band yet (kept across launches).
    @ObservationIgnored private var pending: Bool {
        get { defaults.bool(forKey: Self.pendingKey) }
        set { defaults.set(newValue, forKey: Self.pendingKey) }
    }

    var canAdd: Bool { alarms.count < WenaAlarms.slotCount }

    init() {
        if let data = defaults.data(forKey: Self.alarmsKey),
           let saved = try? JSONDecoder().decode([BandAlarm].self, from: data) {
            alarms = saved
        }
        if pending { status = .waiting }
    }

    // MARK: - Changes (each one is a user action, so it's sent straight away)

    func save(_ alarm: BandAlarm, using connection: BandConnection) async {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else if canAdd {
            alarms.append(alarm)
        }
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        await changed(using: connection)
    }

    func setOn(_ isOn: Bool, for id: BandAlarm.ID, using connection: BandConnection) async {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].isOn = isOn
        await changed(using: connection)
    }

    func delete(_ id: BandAlarm.ID, using connection: BandConnection) async {
        alarms.removeAll { $0.id == id }
        await changed(using: connection)
    }

    /// Called when the band connects: sends a change that couldn't be sent earlier.
    /// Returns a line for the log, or nil if nothing was waiting.
    func sendIfPending(using connection: BandConnection) async -> String? {
        guard pending else { return nil }
        return await send(using: connection) ? "Sent waiting alarm changes" : nil
    }

    // MARK: - Private

    private func changed(using connection: BandConnection) async {
        if let data = try? JSONEncoder().encode(alarms) {
            defaults.set(data, forKey: Self.alarmsKey)
        }
        pending = true
        _ = await send(using: connection)
    }

    private func send(using connection: BandConnection) async -> Bool {
        guard connection.state == .connected, !connection.isSending, !connection.activity.inProgress else {
            status = .waiting
            return false
        }
        status = .sending
        if let error = await connection.sendAlarms(WenaAlarms.packets(for: alarms)) {
            status = .failed(error)
            return false
        }
        pending = false
        status = .sent(at: Date())
        return true
    }
}
