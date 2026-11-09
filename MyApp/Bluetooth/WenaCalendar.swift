import Foundation

/// One calendar event, in plain values (no EventKit), so the packet code can be unit-tested.
nonisolated struct BandCalendarEvent: Equatable {
    let title: String
    let location: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

/// Calendar entry packets for the band (spec section 5). Written to 4002, one per event.
nonisolated enum WenaCalendar {

    /// The band takes up to 255; we send fewer, since its screen shows a short list anyway.
    static let maxEvents = 30
    /// Each text's length goes in one byte (max 255). We keep them much shorter, to suit the
    /// small screen and keep each Bluetooth write small.
    static let maxTitleBytes = 64
    static let maxLocationBytes = 48

    /// The whole list, as packets to send in order: position 1 of N up to N of N.
    /// An empty list becomes the single "no events" packet.
    static func packets(for events: [BandCalendarEvent], calendar: Calendar = .current) -> [Data] {
        let chosen = Array(events.prefix(maxEvents))
        guard !chosen.isEmpty else { return [emptyPacket] }
        return chosen.enumerated().map { index, event in
            entry(event, position: index + 1, total: chosen.count, calendar: calendar)
        }
    }

    /// "No events": position 0, total 0, no texts, zero times (14 bytes).
    static let emptyPacket = Data([0x02] + [UInt8](repeating: 0, count: 13))

    /// One event: 0x02, position (1-based), total, title length, location length, all-day flag,
    /// start and end as Wena timestamps (int32 LE), then the title and location as UTF-8.
    static func entry(_ event: BandCalendarEvent, position: Int, total: Int, calendar: Calendar = .current) -> Data {
        let title = Array(fit(event.title, maxBytes: maxTitleBytes).utf8)
        let location = Array(fit(event.location, maxBytes: maxLocationBytes).utf8)
        let (start, end) = wireTimes(for: event, calendar: calendar)
        var packet = Data([0x02, UInt8(position), UInt8(total), UInt8(title.count), UInt8(location.count),
                           event.isAllDay ? 1 : 0])
        packet.append(littleEndian(WenaPackets.wenaTimestamp(for: start)))
        packet.append(littleEndian(WenaPackets.wenaTimestamp(for: end)))
        packet.append(contentsOf: title)
        packet.append(contentsOf: location)
        return packet
    }

    /// Timed events go as they are. All-day events go as 00:00 UTC of their first date, lasting
    /// whole days, which is how the reference app sends them (spec section 5).
    /// `calendar` is the phone's own calendar, used to read the event's local dates.
    static func wireTimes(for event: BandCalendarEvent, calendar: Calendar) -> (start: Date, end: Date) {
        guard event.isAllDay else { return (event.start, event.end) }
        // iPhone all-day events end at 23:59:59 on their last day (or at the next midnight),
        // so step back one second before taking the last date.
        let firstDay = calendar.dateComponents([.year, .month, .day], from: event.start)
        let lastDay = calendar.dateComponents([.year, .month, .day], from: max(event.start, event.end.addingTimeInterval(-1)))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: firstDay) ?? event.start
        let lastStart = utc.date(from: lastDay) ?? start
        return (start, lastStart.addingTimeInterval(24 * 60 * 60))
    }

    /// Trims spaces and cuts to `maxBytes` of UTF-8 without splitting a character.
    static func fit(_ text: String, maxBytes: Int) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.utf8.count > maxBytes {
            result.removeLast()
        }
        return result
    }

    private static func littleEndian(_ value: Int32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// Debug test: two made-up events starting from `now`.
    static func testEvents(now: Date) -> [BandCalendarEvent] {
        [
            BandCalendarEvent(title: "Anew Link test", location: "Calendar check",
                              start: now.addingTimeInterval(60 * 60), end: now.addingTimeInterval(2 * 60 * 60),
                              isAllDay: false),
            BandCalendarEvent(title: "All-day test", location: "",
                              start: now.addingTimeInterval(24 * 60 * 60), end: now.addingTimeInterval(24 * 60 * 60),
                              isAllDay: true),
        ]
    }
}
