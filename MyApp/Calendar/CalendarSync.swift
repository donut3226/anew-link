import EventKit
import Foundation
import Observation

/// Shows upcoming calendar events on the band (spec section 5).
///
/// The band asks for its calendar about once an hour (request type 1). While the switch is on
/// and calendar access is allowed, we answer with the next 7 days of events (up to 30).
/// Read-only: it never changes the calendar.
@Observable
final class CalendarSync {

    /// The settings key for the "Show calendar on band" switch (also used by `@AppStorage`).
    static let enabledKey = "showCalendarOnBand"
    /// How far ahead to look.
    static let lookAhead: TimeInterval = 7 * 24 * 60 * 60

    enum Status: Equatable {
        case idle
        /// `count` events sent (0 = the "no events" packet). `test` means the debug test list.
        case sent(count: Int, at: Date, test: Bool)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var permissionDenied = false

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var isSending = false

    /// Off until the user switches it on (which is also when calendar access is asked).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    private var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Called when the switch changes. Turning it on asks for access the first time,
    /// then sends the calendar straight away (a user action, so this is also the first test).
    func enabledChanged(connection: BandConnection) async {
        guard isEnabled else { return }
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        permissionDenied = !hasAccess
        if hasAccess {
            _ = await send(using: connection)
        }
    }

    /// The band asked for its calendar. Returns a line for the log, or nil when switched off.
    func answerRequest(connection: BandConnection) async -> String? {
        guard isEnabled else { return nil }
        guard hasAccess else { return "Calendar request not answered: no calendar access" }
        return await send(using: connection)
    }

    /// Debug only: sends two made-up events, to check how the band shows them.
    func sendTest(using connection: BandConnection) async {
        #if DEBUG
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        let packets = WenaCalendar.packets(for: WenaCalendar.testEvents(now: Date()))
        if let error = await connection.sendCalendar(packets) {
            status = .failed(error)
        } else {
            status = .sent(count: packets.count, at: Date(), test: true)
        }
        #endif
    }

    // MARK: - Private

    private func send(using connection: BandConnection) async -> String {
        guard !isSending, connection.state == .connected, !connection.isSending,
              !connection.activity.inProgress else {
            return "Calendar request not answered: busy"
        }
        isSending = true
        defer { isSending = false }

        let events = upcomingEvents()
        let packets = WenaCalendar.packets(for: events)
        if let error = await connection.sendCalendar(packets) {
            status = .failed(error)
            return "Calendar request not answered: \(error)"
        }
        let count = min(events.count, WenaCalendar.maxEvents)
        status = .sent(count: count, at: Date(), test: false)
        // The log notes the count only, never event titles.
        return "Answered calendar request (\(count) events)"
    }

    /// Events that haven't ended yet, from now to 7 days ahead, soonest first.
    private func upcomingEvents() -> [BandCalendarEvent] {
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(Self.lookAhead),
                                                 calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                BandCalendarEvent(title: event.title ?? "", location: event.location ?? "",
                                  start: event.startDate, end: event.endDate, isAllDay: event.isAllDay)
            }
    }
}
