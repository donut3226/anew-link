import Foundation
import Testing
// @testable lets the tests see the app's internal types, such as BandInfoParser.
@testable import MyApp

/// Checks BandInfoParser against Docs/wena3-protocol-spec.md section 4.
/// All byte values here are made up. Never use the real band's serial in tests.
struct BandInfoParserTests {

    // MARK: - Device info (characteristic 1520)

    /// Builds 1520 data: an 8-byte name field (zero-padded), then 4 serial bytes.
    private func infoData(name: String, serial: [UInt8], extra: [UInt8] = []) -> Data {
        var nameField = Array(name.utf8.prefix(8))
        nameField += Array(repeating: 0, count: 8 - nameField.count)
        return Data(nameField + serial + extra)
    }

    @Test func readsFirmwareNameAndLittleEndianSerial() {
        // 78 56 34 12 little-endian is 0x12345678.
        let data = infoData(name: "2.40JP", serial: [0x78, 0x56, 0x34, 0x12])
        let info = BandInfoParser.parseInfo(data)
        #expect(info == BandInfo(firmwareName: "2.40JP", serialNumber: 0x1234_5678))
    }

    @Test func nameCanUseAllEightBytes() {
        let data = infoData(name: "ABCDEFGH", serial: [1, 0, 0, 0])
        #expect(BandInfoParser.parseInfo(data)?.firmwareName == "ABCDEFGH")
    }

    @Test func trailingSpacesAreTrimmed() {
        let data = infoData(name: "2.30JP  ", serial: [1, 0, 0, 0])
        #expect(BandInfoParser.parseInfo(data)?.firmwareName == "2.30JP")
    }

    @Test func serialIsSigned() {
        // The spec says int32, so FF FF FF FF is -1.
        let data = infoData(name: "TEST", serial: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(BandInfoParser.parseInfo(data)?.serialNumber == -1)
    }

    @Test func extraBytesAreIgnored() {
        let data = infoData(name: "TEST", serial: [2, 0, 0, 0], extra: [0xAA, 0xBB])
        #expect(BandInfoParser.parseInfo(data) == BandInfo(firmwareName: "TEST", serialNumber: 2))
    }

    @Test(arguments: [0, 1, 8, 11])
    func tooShortReturnsNil(length: Int) {
        let data = Data(repeating: 0x41, count: length)
        #expect(BandInfoParser.parseInfo(data) == nil)
    }

    // MARK: - Battery (characteristic 1521)

    @Test(arguments: [
        ([66], 66),          // normal reading
        ([0], 0),
        ([100], 100),
        ([101], 100),        // out of range is clamped
        ([0x80], 0),         // signed byte -128, clamped to 0
        ([50, 1, 2], 50),    // further bytes ignored
    ] as [([UInt8], Int)])
    func batteryPercent(bytes: [UInt8], expected: Int) {
        #expect(BandInfoParser.parseBattery(Data(bytes)) == expected)
    }

    @Test func emptyBatteryDataReturnsNil() {
        #expect(BandInfoParser.parseBattery(Data()) == nil)
    }
}
