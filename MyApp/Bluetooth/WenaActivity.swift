import Foundation

/// Data types in the activity stream (spec section 7 and 7.1).
/// Steps and heart rate are confirmed; the others were decoded from our captures of Sony's app
/// (spec 7.1) and some of their meanings are still UNVERIFIED. Events are not decoded.
nonisolated enum ActivityDataType: UInt8 {
    case steps = 0
    case heartRate = 1
    case behaviour = 2
    case vo2 = 3
    case stress = 4
    case bodyEnergy = 5
    case calories = 6
    case events = 7   // the spec lists this one as unknown
}

/// One minute of data from the band (for VO2 Max: one reading for a day).
///
/// Values as the band sends them: steps and heart rate as counts, stress and body energy 0-100,
/// calories in the band's own unit (most likely 1/1000 kcal per minute, UNVERIFIED),
/// VO2 Max in ml/kg/min.
nonisolated struct ActivitySample: Equatable {
    let type: ActivityDataType
    let date: Date
    let value: Int
}

/// One behaviour block (type 2): what the band thinks the wearer was doing from `start` to `end`.
/// The meaning of `kind` is UNVERIFIED (spec 7.1): `01` and `09` were seen during a day; the
/// sleep kinds haven't been captured yet.
nonisolated struct BehaviourRecord: Equatable {
    let kind: UInt8
    let start: Date
    let end: Date
}

// MARK: - Requests (phone to band, written to 3002)

nonisolated extension WenaPackets {

    /// Request A, 17 bytes: 0x01, then "send data newer than" Wena timestamps for
    /// steps, heart rate, behaviour and VO2. A timestamp of 0 means "everything".
    static func activityRequestA(steps: Int32, heartRate: Int32, behaviour: Int32, vo2: Int32) -> Data {
        Data([0x01] + littleEndian(steps) + littleEndian(heartRate) + littleEndian(behaviour) + littleEndian(vo2))
    }

    /// Request B, 17 bytes: 0x02, then timestamps for stress, body energy, calories and events.
    static func activityRequestB(stress: Int32, bodyEnergy: Int32, calories: Int32, events: Int32) -> Data {
        Data([0x02] + littleEndian(stress) + littleEndian(bodyEnergy) + littleEndian(calories) + littleEndian(events))
    }

    /// Start, 1 byte: tells the band to begin streaming.
    static let activityStart = Data([0xFF])

    /// Turns a Wena timestamp back into a Date.
    static func date(fromWenaTimestamp timestamp: Int32) -> Date {
        epoch.addingTimeInterval(TimeInterval(timestamp))
    }

    private static func littleEndian(_ value: Int32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }
}

// MARK: - Packets (band to phone, notifications on 3002)

/// One packet from the activity stream:
/// sequence (1 byte), CRC-16 (2 bytes, little-endian), kind (1 byte), payload.
nonisolated struct ActivityPacket: Equatable {

    enum Kind: UInt8 {
        case header = 0
        case data = 1
        case finish = 2
    }

    let sequence: UInt8
    let kindByte: UInt8
    let payload: [UInt8]
    /// True if the CRC the band sent matches the one we work out from kind + payload.
    let crcIsValid: Bool

    var kind: Kind? { Kind(rawValue: kindByte) }

    /// Returns nil if the data is too short to be a packet.
    init?(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        sequence = bytes[0]
        let sentCRC = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        kindByte = bytes[3]
        payload = Array(bytes[4...])
        crcIsValid = WenaCRC16.checksum(bytes[3...]) == sentCRC
    }
}

/// Puts the activity stream back together, one packet at a time.
///
/// This is a "state machine": it remembers where it is (which data type, which minute)
/// and each new packet moves it along. It has no Bluetooth code, so tests can feed it made-up packets.
nonisolated struct ActivityStreamAssembler {

    /// What happened with the packet just fed in.
    enum Event: Equatable {
        case accepted   // used (or harmlessly skipped)
        case ignored    // before the start of a sync, or too short
        case badCRC     // damaged, dropped
        case gap        // a packet went missing: the sync should be discarded
        case finished   // the band says it's done
    }

    private(set) var samples: [ActivitySample] = []
    private(set) var behaviours: [BehaviourRecord] = []
    private(set) var packetCount = 0
    private(set) var badCRCCount = 0

    private var started = false
    private var expectedSequence: UInt8 = 0
    private var currentType: ActivityDataType?
    /// Wena timestamp of the next sample in the current block.
    private var nextSampleTime: Int32?
    /// Bytes of a record that continues in the next packet (record types only).
    private var carry: [UInt8] = []

    mutating func feed(_ data: Data) -> Event {
        guard let packet = ActivityPacket(data) else { return .ignored }

        // Sequence check. 0xFF marks the first packet of a sync, then 0, 1 ... 0x7F, then 0 again.
        if packet.sequence == 0xFF {
            self = ActivityStreamAssembler()
            started = true
            expectedSequence = 0
        } else {
            guard started else { return .ignored }
            guard packet.sequence == expectedSequence else { return .gap }
            expectedSequence = packet.sequence == 0x7F ? 0 : packet.sequence + 1
        }
        packetCount += 1

        guard packet.crcIsValid else {
            badCRCCount += 1
            return .badCRC
        }

        switch packet.kind {
        case .header:
            startBlock(packet.payload)
        case .data:
            addSamples(packet.payload)
        case .finish:
            return .finished
        case nil:
            break   // unknown kind: skip it
        }
        return .accepted
    }

    /// Header payload: data type (1 byte), then usually the start time (int32).
    private mutating func startBlock(_ payload: [UInt8]) {
        guard let typeByte = payload.first else { return }
        currentType = ActivityDataType(rawValue: typeByte)
        carry = []
        if payload.count >= 5 {
            let raw = UInt32(payload[1]) | UInt32(payload[2]) << 8 | UInt32(payload[3]) << 16 | UInt32(payload[4]) << 24
            nextSampleTime = Int32(bitPattern: raw)
        } else {
            nextSampleTime = nil
        }
    }

    /// Adds one data packet to the current block, by type (spec 7 and 7.1).
    private mutating func addSamples(_ payload: [UInt8]) {
        guard let type = currentType else { return }
        switch type {
        case .steps, .heartRate, .stress, .bodyEnergy:
            addPerMinute(payload, type: type, size: 1)
        case .calories:
            addPerMinute(payload, type: type, size: 2)
        case .vo2:
            // 5-byte records: int32 date, then VO2 Max (ml/kg/min). 0 would be no reading.
            for record in records(payload, size: 5) {
                let value = Int(record[record.startIndex + 4])
                guard value > 0 else { continue }
                samples.append(ActivitySample(type: .vo2, date: WenaPackets.date(fromWenaTimestamp: Self.int32(record, at: 0)),
                                              value: value))
            }
        case .behaviour:
            // 13-byte records: kind, then end, start, end again (int32 each).
            for record in records(payload, size: 13) {
                let start = Self.int32(record, at: 5), end = Self.int32(record, at: 9)
                guard end >= start else { continue }
                behaviours.append(BehaviourRecord(kind: record[record.startIndex],
                                                  start: WenaPackets.date(fromWenaTimestamp: start),
                                                  end: WenaPackets.date(fromWenaTimestamp: end)))
            }
        case .events:
            break   // 8-byte records whose meaning is unknown (spec 7.1)
        }
    }

    /// One value per minute (1 or 2 bytes, little-endian), continuing from the header's time.
    private mutating func addPerMinute(_ payload: [UInt8], type: ActivityDataType, size: Int) {
        guard var time = nextSampleTime else { return }
        for record in records(payload, size: size) {
            let first = record.startIndex
            let value = size == 2 ? Int(record[first]) | Int(record[first + 1]) << 8 : Int(record[first])
            if Self.isReading(value, type: type) {
                samples.append(ActivitySample(type: type, date: WenaPackets.date(fromWenaTimestamp: time), value: value))
            }
            time &+= 60   // &+= can't crash on overflow, even with nonsense data
        }
        nextSampleTime = time
    }

    /// False for values that mean "no reading": heart rate 0 (spec 7), stress 127 (`7F`, the only
    /// stress value seen so far, UNVERIFIED) and anything over 100 for body energy.
    static func isReading(_ value: Int, type: ActivityDataType) -> Bool {
        switch type {
        case .heartRate: value != 0
        case .stress: value != 0x7F && value <= 100
        case .bodyEnergy: value <= 100
        default: true
        }
    }

    /// Splits the payload into fixed-size records, keeping a partial record for the next packet.
    private mutating func records(_ payload: [UInt8], size: Int) -> [ArraySlice<UInt8>] {
        let bytes = carry + payload
        let whole = bytes.count / size * size
        carry = Array(bytes[whole...])
        return stride(from: 0, to: whole, by: size).map { bytes[$0..<$0 + size] }
    }

    private static func int32(_ record: ArraySlice<UInt8>, at offset: Int) -> Int32 {
        let i = record.startIndex + offset
        let raw = UInt32(record[i]) | UInt32(record[i + 1]) << 8 | UInt32(record[i + 2]) << 16 | UInt32(record[i + 3]) << 24
        return Int32(bitPattern: raw)
    }
}
