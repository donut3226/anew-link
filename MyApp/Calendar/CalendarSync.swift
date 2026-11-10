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
    /// The settings key for the calendars the user switched off (identifiers). An exclusion list,
    /// so a calendar added later is shown until switched off.
    static let excludedKey = "calendarSync.excludedCalendars"
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

    // MARK: - Choosing calendars

    /// The phone's calendars, with whether each one goes to the band. Empty without access.
    var choices: [CalendarChoice] {
        guard hasAccess else { return [] }
        let excluded = Self.excluded
        return store.calendars(for: .event)
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "",
                                  isIncluded: !excluded.contains($0.calendarIdentifier)) }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    /// The user ticked or unticked a calendar: save it and send the calendar again (a user action).
    func setIncluded(_ included: Bool, calendarID: String, connection: BandConnection) async {
        Self.excluded = CalendarChoice.updatedExclusions(Self.excluded, id: calendarID, included: included)
        refreshTick += 1
        if isEnabled, hasAccess {
            _ = await send(using: connection)
        }
    }

    /// Bumped on every change so SwiftUI redraws `choices` (which reads EventKit, not stored state).
    private(set) var refreshTick = 0

    private static var excluded: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: excludedKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: excludedKey) }
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
        let excluded = Self.excluded
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        // An empty list would mean "all calendars" to EventKit, so no calendars means no events.
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(Self.lookAhead),
                                                 calendars: calendars)
        return store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                BandCalendarEvent(title: event.title ?? "", location: event.location ?? "",
                                  start: event.startDate, end: event.endDate, isAllDay: event.isAllDay)
            }
    }
}

/// One of the phone's calendars, for the "Calendars" list.
nonisolated struct CalendarChoice: Equatable, Identifiable {
    let id: String
    let title: String
    let account: String
    var isIncluded: Bool

    /// The exclusion list after ticking (`included`) or unticking one calendar.
    static func updatedExclusions(_ excluded: Set<String>, id: String, included: Bool) -> Set<String> {
        included ? excluded.subtracting([id]) : excluded.union([id])
    }
}
