import Foundation
import Testing
@testable import MyApp

/// Checks WenaPackets against Docs/wena3-protocol-spec.md sections 3 and 4.
struct WenaPacketsTests {

    /// Makes a UTC date from an ISO 8601 string such as "2026-11-08T00:00:00Z".
    private func utc(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    // MARK: - Wena timestamp

    @Test func epochIsZero() throws {
        #expect(WenaPackets.wenaTimestamp(for: try utc("2020-01-01T00:00:00Z")) == 0)
    }

    @Test func oneSecondAfterEpochIsOne() throws {
        #expect(WenaPackets.wenaTimestamp(for: try utc("2020-01-01T00:00:01Z")) == 1)
    }

    @Test func knownDate() throws {
        #expect(WenaPackets.wenaTimestamp(for: try utc("2026-11-08T00:00:00Z")) == 216_259_200)
    }

    @Test func fractionsOfASecondRoundDown() throws {
        let date = try utc("2020-01-01T00:00:01Z").addingTimeInterval(0.9)
        #expect(WenaPackets.wenaTimestamp(for: date) == 1)
    }

    // MARK: - Set time packet

    @Test func setTimePacketBytes() throws {
        let packet = WenaPackets.setTime(try utc("2026-11-08T00:00:00Z"))
        #expect(packet == Data([0x10, 0x80, 0xDA, 0xE3, 0x0C]))
    }

    // MARK: - Set time zone packet

    @Test(arguments: [
        (11 * 3600, [0x11, 0x0B, 0x00]),          // Sydney summer, +11:00
        (10 * 3600 + 1800, [0x11, 0x0A, 0x1E]),   // Adelaide summer, +10:30
        (8 * 3600, [0x11, 0x08, 0x00]),           // Perth, +8:00
        (5 * 3600 + 2700, [0x11, 0x05, 0x2D]),    // Nepal, +5:45
        (0, [0x11, 0x00, 0x00]),                  // UTC
        (-5 * 3600, [0x11, 0xFB, 0x00]),          // New York winter, -5:00
    ] as [(Int, [UInt8])])
    func timeZonePacketBytes(secondsFromGMT: Int, expected: [UInt8]) {
        #expect(WenaPackets.setTimeZone(secondsFromGMT: secondsFromGMT) == Data(expected))
    }

    @Test(arguments: [-(3 * 3600 + 1800), -(9 * 3600 + 1800)])
    func unverifiedNegativeHalfHourZonesAreNotSent(secondsFromGMT: Int) {
        // -3:30 (Newfoundland) and -9:30 (Marquesas): the spec marks these UNVERIFIED.
        #expect(WenaPackets.setTimeZone(secondsFromGMT: secondsFromGMT) == nil)
    }
}
