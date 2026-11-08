import Foundation
import Testing
@testable import MyApp

/// Checks the weather packet against Docs/wena3-protocol-spec.md section 5.
struct WenaWeatherTests {

    // MARK: - Temperature byte (Fahrenheit, rounded, + 100)

    @Test(arguments: [
        (0.0, 132),      // 32 F
        (25.0, 177),     // 77 F
        (-10.0, 114),    // 14 F
        (37.8, 200),     // 100.04 F rounds to 100
        (-200.0, 0),     // far below range, kept at 0
        (200.0, 255),    // far above range, kept at 255
    ] as [(Double, UInt8)])
    func temperatureByte(celsius: Double, expected: UInt8) {
        #expect(WenaWeather.temperatureByte(celsius: celsius) == expected)
    }

    // MARK: - Condition byte ((main << 3) | sub)

    @Test(arguments: [
        (0, 0x00),                                   // clear: sunny + sunny
        (1, 0x01), (2, 0x01), (45, 0x01), (48, 0x01), // partly cloudy, fog: sunny + cloudy
        (3, 0x09),                                   // overcast: cloudy + cloudy
        (51, 0x12), (57, 0x12), (61, 0x12), (63, 0x12), (80, 0x12), (81, 0x12), // rain
        (65, 0x1B), (82, 0x1B), (95, 0x1B), (99, 0x1B), // heavy rain, thunderstorm
        (66, 0x14), (67, 0x14),                      // freezing rain: rain + snow
        (71, 0x24), (77, 0x24), (85, 0x24), (86, 0x24), // snow
        (12345, 0x09),                               // unknown: cloudy
    ] as [(Int, UInt8)])
    func conditionByteForOpenMeteoCode(code: Int, expected: UInt8) {
        let condition = WenaWeather.condition(forOpenMeteoCode: code)
        #expect(WenaWeather.conditionByte(main: condition.main, sub: condition.sub) == expected)
    }

    // MARK: - Weather packet

    @Test func testPatternPacketBytes() throws {
        let packet = try #require(WenaPackets.weather(days: WenaPackets.testWeatherDays))
        #expect(packet == Data([
            0x03,
            0x00, 0x00, 0x9F, 0xB1,   // sunny, 15 / 25 C
            0x09, 0x09, 0x96, 0xA8,   // cloudy, 10 / 20 C
            0x12, 0x12, 0x8D, 0x9F,   // rain, 5 / 15 C
            0x1B, 0x1B, 0x84, 0x96,   // heavy rain, 0 / 10 C
            0x24, 0x24, 0x7B, 0x84,   // snow, -5 / 0 C
        ]))
        #expect(packet.count == 21)
    }

    @Test(arguments: [0, 4, 6])
    func packetNeedsExactlyFiveDays(count: Int) {
        let day = WenaWeatherDay(main: .sunny, sub: .sunny, minCelsius: 10, maxCelsius: 20)
        #expect(WenaPackets.weather(days: Array(repeating: day, count: count)) == nil)
    }
}
