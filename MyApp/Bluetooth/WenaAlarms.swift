import Foundation

/// One of the band's vibrating alarms (spec section 9), in plain values so it can be saved and tested.
nonisolated struct BandAlarm: Codable, Equatable, Identifiable {
    var id = UUID()
    var isOn = true
    var hour = 7
    var minute = 0
    /// Weekdays it repeats on, using Calendar numbering: 1 Sunday, 2 Monday ... 7 Saturday.
    /// Empty means "once".
    var repeatDays: Set<Int> = []
    /// Smart wake-up: the band may vibrate up to this many minutes early, in light sleep. 0 = off.
    var smartWakeupMinutes = 0

    /// The reference app's default smart wake-up window.
    static let defaultSmartWakeupMinutes = 10
}

/// Builds the alarm packets for the control characteristic 1514 (spec section 9).
nonisolated enum WenaAlarms {

    /// The band has 9 alarm slots, sent as three packets of 3 slots each.
    static let slotCount = 9
    static let slotsPerPacket = 3

    /// All three packets, in order. Sending them replaces every alarm on the band,
    /// so the full list is always sent; slots without an alarm are sent empty.
    static func packets(for alarms: [BandAlarm]) -> [Data] {
        let chosen = Array(alarms.prefix(slotCount))
        return stride(from: 0, to: slotCount, by: slotsPerPacket).map { first in
            var packet = Data([0x06])
            for slot in first..<(first + slotsPerPacket) {
                packet.append(UInt8(slot))
                packet.append(contentsOf: slot < chosen.count ? slotBytes(chosen[slot]) : [0, 0, 0, 0, 0])
            }
            return packet
        }
    }

    /// state (0x02 on, 0x01 off), repeat days, smart wake-up minutes, hour, minute.
    static func slotBytes(_ alarm: BandAlarm) -> [UInt8] {
        [alarm.isOn ? 0x02 : 0x01,
         repeatMask(alarm.repeatDays),
         UInt8(clamping: alarm.smartWakeupMinutes),
         UInt8(clamping: alarm.hour),
         UInt8(clamping: alarm.minute)]
    }

    /// Bit 0 Sunday, bit 1 Monday ... bit 6 Saturday (Calendar weekday minus 1).
    static func repeatMask(_ days: Set<Int>) -> UInt8 {
        days.filter { (1...7).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
    }
}
