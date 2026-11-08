import Foundation
import Testing
@testable import MyApp

/// Checks activity sync packets and stream handling against spec section 7.
/// All data is made up.
struct WenaActivityTests {

    // MARK: - Helpers that build packets the way the band would

    /// sequence, CRC (over kind + payload, little-endian), kind, payload.
    private func packet(_ sequence: UInt8, kind: UInt8, _ payload: [UInt8], corruptCRC: Bool = false) -> Data {
        var crc = WenaCRC16.checksum([kind] + payload)
        if corruptCRC { crc ^= 0x0001 }
        return Data([sequence, UInt8(crc & 0xFF), UInt8(crc >> 8), kind] + payload)
    }

    private func header(_ sequence: UInt8, type: UInt8, start: Int32) -> Data {
        let time = withUnsafeBytes(of: start.littleEndian) { Array($0) }
        return packet(sequence, kind: 0, [type] + time)
    }

    private func data(_ sequence: UInt8, _ values: [UInt8]) -> Data {
        packet(sequence, kind: 1, values)
    }

    private func finish(_ sequence: UInt8) -> Data {
        packet(sequence, kind: 2, [])
    }

    private let start: Int32 = 216_259_200   // 2026-11-08 00:00 UTC
    private var startDate: Date { WenaPackets.date(fromWenaTimestamp: start) }

    // MARK: - Requests

    @Test func requestABytes() {
        let packet = WenaPackets.activityRequestA(steps: 1, heartRate: 0x0102_0304, behaviour: -1, vo2: 0)
        #expect(packet == Data([0x01,
                                0x01, 0x00, 0x00, 0x00,
                                0x04, 0x03, 0x02, 0x01,
                                0xFF, 0xFF, 0xFF, 0xFF,
                                0x00, 0x00, 0x00, 0x00]))
    }

    @Test func requestBBytes() {
        let packet = WenaPackets.activityRequestB(stress: 2, bodyEnergy: 3, calories: 4, events: 5)
        #expect(packet == Data([0x02, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0]))
    }

    @Test func startIsFF() {
        #expect(WenaPackets.activityStart == Data([0xFF]))
    }

    @Test func wenaTimestampRoundTrip() {
        let date = WenaPackets.date(fromWenaTimestamp: start)
        #expect(WenaPackets.wenaTimestamp(for: date) == start)
    }

    // MARK: - Packet

    @Test func packetSplitsFields() throws {
        let parsed = try #require(ActivityPacket(data(5, [10, 20])))
        #expect(parsed.sequence == 5)
        #expect(parsed.kind == .data)
        #expect(parsed.payload == [10, 20])
        #expect(parsed.crcIsValid)
    }

    @Test func badCRCIsFlagged() throws {
        let parsed = try #require(ActivityPacket(packet(5, kind: 1, [10], corruptCRC: true)))
        #expect(!parsed.crcIsValid)
    }

    @Test func tooShortIsRejected() {
        #expect(ActivityPacket(Data([0xFF, 0x00, 0x00])) == nil)
    }

    // MARK: - Assembler

    @Test func stepsAreOneMinuteApartAcrossPackets() {
        var assembler = ActivityStreamAssembler()
        #expect(assembler.feed(header(0xFF, type: 0, start: start)) == .accepted)
        #expect(assembler.feed(data(0, [5, 0, 7])) == .accepted)
        #expect(assembler.feed(data(1, [9])) == .accepted)
        #expect(assembler.feed(finish(2)) == .finished)

        #expect(assembler.samples == [
            ActivitySample(type: .steps, date: startDate, value: 5),
            ActivitySample(type: .steps, date: startDate.addingTimeInterval(60), value: 0),
            ActivitySample(type: .steps, date: startDate.addingTimeInterval(120), value: 7),
            ActivitySample(type: .steps, date: startDate.addingTimeInterval(180), value: 9),
        ])
        #expect(assembler.packetCount == 4)
    }

    @Test func heartRateZeroIsSkipped() {
        var assembler = ActivityStreamAssembler()
        _ = assembler.feed(header(0xFF, type: 1, start: start))
        _ = assembler.feed(data(0, [60, 0, 62]))
        #expect(assembler.samples == [
            ActivitySample(type: .heartRate, date: startDate, value: 60),
            ActivitySample(type: .heartRate, date: startDate.addingTimeInterval(120), value: 62),
        ])
    }

    @Test func twoBlocksOfDifferentTypes() {
        var assembler = ActivityStreamAssembler()
        _ = assembler.feed(header(0xFF, type: 0, start: start))
        _ = assembler.feed(data(0, [3]))
        _ = assembler.feed(header(1, type: 1, start: start + 600))
        _ = assembler.feed(data(2, [70]))
        #expect(assembler.samples == [
            ActivitySample(type: .steps, date: startDate, value: 3),
            ActivitySample(type: .heartRate, date: startDate.addingTimeInterval(600), value: 70),
        ])
    }

    @Test func packetsBeforeStartAreIgnored() {
        var assembler = ActivityStreamAssembler()
        #expect(assembler.feed(data(0, [1])) == .ignored)
        #expect(assembler.packetCount == 0)
    }

    @Test func sequenceWrapsFrom7FToZero() {
        var assembler = ActivityStreamAssembler()
        _ = assembler.feed(header(0xFF, type: 0, start: start))
        for sequence in UInt8(0)...0x7F {
            #expect(assembler.feed(data(sequence, [1])) == .accepted)
        }
        #expect(assembler.feed(data(0, [1])) == .accepted)   // wrapped
        #expect(assembler.samples.count == 129)
    }

    @Test func missingPacketIsAGap() {
        var assembler = ActivityStreamAssembler()
        _ = assembler.feed(header(0xFF, type: 0, start: start))
        _ = assembler.feed(data(0, [1]))
        #expect(assembler.feed(data(2, [1])) == .gap)   // 1 is missing
    }

    @Test func badCRCIsDroppedButSyncContinues() {
        var assembler = ActivityStreamAssembler()
        _ = assembler.feed(header(0xFF, type: 0, start: start))
        #expect(assembler.feed(packet(0, kind: 1, [50], corruptCRC: true)) == .badCRC)
        #expect(assembler.feed(data(1, [4])) == .accepted)
        #expect(assembler.badCRCCount == 1)
        #expect(assembler.samples.map(\.value) == [4])
    }

    @Test func undecodedTypesAreIgnored() {
        var assembler = ActivityStreamAssembler()
        _ = assembler.feed(header(0xFF, type: 3, start: start))   // VO2
        #expect(assembler.feed(data(0, [40, 41])) == .accepted)
        #expect(assembler.samples.isEmpty)
    }

    @Test func newFFStartsAFreshSync() {
        var assembler = ActivityStreamAssembler()
        _ = assembler.feed(header(0xFF, type: 0, start: start))
        _ = assembler.feed(data(0, [8]))
        _ = assembler.feed(header(0xFF, type: 0, start: start))
        #expect(assembler.samples.isEmpty)
        #expect(assembler.packetCount == 1)
    }

    // MARK: - Firmware guard

    @Test(arguments: [
        ("2.40JP", true),
        ("2.41JP", true),
        ("3.00JP", true),
        ("2.30JP", false),
        ("1.02JP", false),
    ])
    func firmwareSupport(name: String, supported: Bool) {
        #expect(BandInfo(firmwareName: name, serialNumber: 0).supportsActivitySync == supported)
    }

    @Test func unreadableFirmwareIsUnknown() {
        #expect(BandInfo(firmwareName: "PREVIEW", serialNumber: 0).supportsActivitySync == nil)
    }
}
