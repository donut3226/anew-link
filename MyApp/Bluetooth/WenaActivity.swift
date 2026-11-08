import Foundation

/// Data types in the activity stream (spec section 7).
/// We only decode steps and heart rate so far; the rest are listed so we can ignore them safely.
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

/// One minute of data from the band.
nonisolated struct ActivitySample: Equatable {
    let type: ActivityDataType
    let date: Date
    let value: Int
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
    private(set) var packetCount = 0
    private(set) var badCRCCount = 0

    private var started = false
    private var expectedSequence: UInt8 = 0
    private var currentType: ActivityDataType?
    /// Wena timestamp of the next sample in the current block.
    private var nextSampleTime: Int32?

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
        if payload.count >= 5 {
            let raw = UInt32(payload[1]) | UInt32(payload[2]) << 8 | UInt32(payload[3]) << 16 | UInt32(payload[4]) << 24
            nextSampleTime = Int32(bitPattern: raw)
        } else {
            nextSampleTime = nil
        }
    }

    /// Steps and heart rate: one unsigned byte per minute, continuing from the header's time.
    private mutating func addSamples(_ payload: [UInt8]) {
        guard let type = currentType, type == .steps || type == .heartRate,
              var time = nextSampleTime else { return }
        for byte in payload {
            // A heart rate of 0 presumably means "no reading" (spec section 7).
            if !(type == .heartRate && byte == 0) {
                samples.append(ActivitySample(type: type,
                                              date: WenaPackets.date(fromWenaTimestamp: time),
                                              value: Int(byte)))
            }
            time &+= 60   // &+= can't crash on overflow, even with nonsense data
        }
        nextSampleTime = time
    }
}
