import Foundation

/// LED colours for a notification (spec 15.5; the same values as the section 8 notification packet).
nonisolated enum NotifyColour: UInt8, Codable, CaseIterable, Identifiable {
    case red = 0x01, yellow = 0x02, green = 0x03, cyan = 0x04, blue = 0x05, purple = 0x06, white = 0x07
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .red: "Red"
        case .yellow: "Yellow"
        case .green: "Green"
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .purple: "Purple"
        case .white: "White"
        }
    }
}

/// Vibration patterns (spec 15.5). Sony's "Short" is left out: its byte (`01` or `09`) wasn't captured.
/// `callDefault` (`01`) is what Sony sends for calls, and is only offered for calls.
nonisolated enum NotifyPattern: UInt8, Codable, CaseIterable, Identifiable {
    case nothing = 0x00, callDefault = 0x01, basic = 0x02, rapid = 0x03, triple = 0x04
    case stepUp = 0x05, stepDown = 0x06, warning = 0x07, siren = 0x08, double = 0x0A
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .nothing: "Nothing"
        case .callDefault: "Call (standard)"
        case .basic: "Basic"
        case .rapid: "Rapid"
        case .triple: "Triple"
        case .stepUp: "Step up"
        case .stepDown: "Step down"
        case .warning: "Warning"
        case .siren: "Siren"
        case .double: "Double"
        }
    }
    /// In the order Sony's app lists them.
    static let forApps: [NotifyPattern] = [.nothing, .basic, .double, .triple, .rapid, .stepUp, .stepDown, .warning, .siren]
    static let forCalls: [NotifyPattern] = [.callDefault] + forApps
}

/// How many times the band vibrates (spec 15.5). "4 times" is left out until it's captured.
nonisolated enum NotifyCount: UInt8, Codable, CaseIterable, Identifiable {
    case repeating = 0x00, once = 0x01, twice = 0x02, threeTimes = 0x03
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .repeating: "Repeat"
        case .once: "Once"
        case .twice: "Twice"
        case .threeTimes: "3 times"
        }
    }
}

/// One entry in the band's notification list: an iPhone app, or phone calls.
nonisolated struct NotifyApp: Codable, Equatable, Identifiable, Hashable {
    enum Kind: UInt8, Codable { case app = 0x00, call = 0x01 }

    var id = UUID()
    var kind: Kind = .app
    /// The app's name exactly as iOS shows it (the band matches ANCS notifications by name).
    var name: String
    var colour: NotifyColour = .white
    var pattern: NotifyPattern = .basic
    var count: NotifyCount = .once
    var isOn = true

    /// Calls, as Sony's app sets them: white, the call pattern, repeating.
    static func call() -> NotifyApp {
        NotifyApp(kind: .call, name: "phone", colour: .white, pattern: .callDefault, count: .repeating)
    }

    var displayName: String { kind == .call ? "Calls" : name }
}

/// Builds the per-app notification list for the band (spec 15.3), written to the characteristic
/// right after 1514 in service 1501 (handle `0x102B` in our capture).
nonisolated enum WenaNotificationList {

    /// Most apps the list holds. Sony's limit is unknown (**UNVERIFIED**); 20 is a safe guess.
    static let maxApps = 20
    /// Longest name in UTF-8 bytes. Sony's limit is unknown; 31 matches the notification title limit.
    static let maxNameBytes = 31
    /// Bytes of record per write (each write is fragment number, byte count, then up to 18 bytes).
    static let fragmentSize = 18
    /// The lone byte that ends the list.
    static let endOfList = Data([0x04])
    /// Sent to 1514 after the list, exactly as Sony's app does: notifications on, calendar on
    /// (spec 15.4). Only this exact packet; a `00` in either field is never sent.
    static let notificationsAndCalendarOn = Data([0x12, 0x01, 0x01])

    /// Common iPhone apps, with their names as iOS shows them.
    static let presets = [
        "Messages", "Mail", "Calendar", "Reminders", "WhatsApp", "LINE", "Gmail", "Outlook",
        "Slack", "Teams", "Messenger", "Instagram", "Telegram", "Signal", "Discord", "X",
        "Facebook", "WeChat", "Proton Mail", "Google Calendar",
    ]

    /// The list a new install starts with: a few common messaging apps, then calls.
    static func defaultList() -> [NotifyApp] {
        ["Messages", "Mail", "WhatsApp", "LINE", "Gmail"].map { NotifyApp(name: $0) } + [NotifyApp.call()]
    }

    /// Apps first in the user's order, calls always last.
    static func ordered(_ list: [NotifyApp]) -> [NotifyApp] {
        Array(list.filter { $0.kind == .app }.prefix(maxApps)) + list.filter { $0.kind == .call }.prefix(1)
    }

    /// One record: kind, name length, name, colour, `03`, pattern, count, on (1/0), then the
    /// position as int16 little-endian.
    static func record(_ app: NotifyApp, index: Int) -> Data {
        let name = app.kind == .call ? Array("phone".utf8) : nameBytes(app.name)
        var data = Data([app.kind.rawValue, UInt8(name.count)])
        data.append(contentsOf: name)
        data.append(contentsOf: [app.colour.rawValue, 0x03, app.pattern.rawValue, app.count.rawValue, app.isOn ? 1 : 0])
        withUnsafeBytes(of: UInt16(clamping: index).littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    /// Splits a record into writes of `[fragment][byte count][up to 18 bytes]`.
    /// A record that fills its last fragment exactly is followed by an empty one.
    static func fragments(_ record: Data) -> [Data] {
        let bytes = [UInt8](record)
        var writes = stride(from: 0, to: bytes.count, by: fragmentSize).enumerated().map { number, start in
            let chunk = bytes[start..<min(start + fragmentSize, bytes.count)]
            return Data([UInt8(number), UInt8(chunk.count)] + chunk)
        }
        if bytes.count % fragmentSize == 0 {
            writes.append(Data([UInt8(writes.count), 0x00]))
        }
        return writes
    }

    /// Every write for the whole list, in order: each record's fragments, then the lone `04`.
    /// Positions count down to 0, so calls (always last) are 0.
    static func packets(for list: [NotifyApp]) -> [Data] {
        let entries = ordered(list)
        var writes: [Data] = []
        for (offset, app) in entries.enumerated() {
            writes += fragments(record(app, index: entries.count - 1 - offset))
        }
        writes.append(endOfList)
        return writes
    }

    /// The name as UTF-8, cut at a character boundary to `maxNameBytes`.
    static func nameBytes(_ name: String) -> [UInt8] {
        var result: [UInt8] = []
        for character in name.trimmingCharacters(in: .whitespaces) {
            let next = Array(String(character).utf8)
            if result.count + next.count > maxNameBytes { break }
            result += next
        }
        return result
    }
}
