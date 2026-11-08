import Foundation

/// A request the band sends to the phone on characteristic 4002 (spec section 6).
/// The first byte is the request type.
nonisolated struct BandRequest: Equatable {

    let type: UInt8
    /// Only for type 10 ("remove notification"): the int32 notification id that follows.
    let notificationID: Int32?

    /// Returns nil for empty data.
    init?(_ data: Data) {
        let bytes = [UInt8](data)
        guard let first = bytes.first else { return nil }
        type = first
        if first == 10, bytes.count >= 5 {
            let raw = UInt32(bytes[1]) | UInt32(bytes[2]) << 8 | UInt32(bytes[3]) << 16 | UInt32(bytes[4]) << 24
            notificationID = Int32(bitPattern: raw)
        } else {
            notificationID = nil
        }
    }

    /// Plain-words name for the log.
    var name: String {
        Self.name(forType: type)
    }

    static func name(forType type: UInt8) -> String {
        switch type {
        case 0: "Sync tick"
        case 1: "Get calendar"
        case 2: "Locate phone"
        case 3: "Get weather"
        case 4: "Riiiver side button"
        case 5: "Riiiver home icon"
        case 6: "Unknown (payment?)"
        case 10: "Remove notification"
        case 11: "Music info"
        default: "Unknown type \(type)"
        }
    }
}
