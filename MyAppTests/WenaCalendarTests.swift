import Foundation
import Testing
@testable import MyApp

/// Checks the calendar entry packets against spec section 5. Made-up events only.
struct WenaCalendarTests {

    private func at(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    /// A phone calendar in Sydney (UTC+11 in November), to check all-day dates don't slip a day.
    private var sydney: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return calendar
    }

    @Test func timedEventBytes() throws {
        let event = BandCalendarEvent(title: "Gym", location: "Park",
                                      start: try at("2026-11-10T09:00:00Z"), end: try at("2026-11-10T10:30:00Z"),
                                      isAllDay: false)
        let packet = WenaCalendar.entry(event, position: 1, total: 2, calendar: sydney)
        #expect([UInt8](packet) == [0x02, 0x01, 0x02, 0x03, 0x04, 0x00,
                                    0x10, 0xFC, 0xE6, 0x0C,   // start
                                    0x28, 0x11, 0xE7, 0x0C]   // end
                                   + Array("Gym".utf8) + Array("Park".utf8))
    }

    @Test func allDayEventIsMidnightUTCOfItsLocalDates() throws {
        // 12 and 13 Nov in Sydney: local midnight 12 Nov is 13:00 UTC on 11 Nov, and the event
        // ends at 23:59:59 local on 13 Nov.
        let event = BandCalendarEvent(title: "", location: "",
                                      start: try at("2026-11-11T13:00:00Z"), end: try at("2026-11-13T12:59:59Z"),
                                      isAllDay: true)
        let packet = [UInt8](WenaCalendar.entry(event, position: 1, total: 1, calendar: sydney))
        #expect(packet[5] == 0x01)
        #expect(Array(packet[6..<10]) == [0x80, 0x20, 0xE9, 0x0C])    // 12 Nov 00:00 UTC
        #expect(Array(packet[10..<14]) == [0x80, 0xC3, 0xEB, 0x0C])   // 14 Nov 00:00 UTC (two whole days)
    }

    @Test func allDayEndingAtNextMidnightIsTheSameLength() throws {
        let event = BandCalendarEvent(title: "", location: "",
                                      start: try at("2026-11-11T13:00:00Z"), end: try at("2026-11-13T13:00:00Z"),
                                      isAllDay: true)
        let packet = [UInt8](WenaCalendar.entry(event, position: 1, total: 1, calendar: sydney))
        #expect(Array(packet[10..<14]) == [0x80, 0xC3, 0xEB, 0x0C])
    }

    @Test func emptyListIsTheNoEventsPacket() {
        #expect([UInt8](WenaCalendar.packets(for: [])[0]) == [0x02] + [UInt8](repeating: 0, count: 13))
        #expect(WenaCalendar.packets(for: []).count == 1)
    }

    @Test func listIsNumberedFromOneAndCapped() throws {
        let start = try at("2026-11-10T09:00:00Z")
        let events = (0..<40).map { i in
            BandCalendarEvent(title: "E\(i)", location: "", start: start, end: start, isAllDay: false)
        }
        let packets = WenaCalendar.packets(for: events)
        #expect(packets.count == WenaCalendar.maxEvents)
        #expect(packets.first?[1] == 1)
        #expect(packets.last?[1] == UInt8(WenaCalendar.maxEvents))
        #expect(packets.allSatisfy { $0[2] == UInt8(WenaCalendar.maxEvents) })
    }

    @Test func longTextsAreCutWithoutSplittingCharacters() throws {
        let title = String(repeating: "予定", count: 40)   // 240 bytes
        let event = BandCalendarEvent(title: title, location: String(repeating: "x", count: 100),
                                      start: try at("2026-11-10T09:00:00Z"), end: try at("2026-11-10T10:00:00Z"),
                                      isAllDay: false)
        let packet = [UInt8](WenaCalendar.entry(event, position: 1, total: 1, calendar: sydney))
        let titleLength = Int(packet[3]), locationLength = Int(packet[4])
        #expect(titleLength <= WenaCalendar.maxTitleBytes)
        #expect(locationLength == WenaCalendar.maxLocationBytes)
        #expect(packet.count == 14 + titleLength + locationLength)
        #expect(String(bytes: packet[14..<(14 + titleLength)], encoding: .utf8) != nil)
    }
}
