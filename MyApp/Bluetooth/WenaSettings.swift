import Foundation

/// A clock time on the band (hour and minute), for the do not disturb and auto power off windows.
nonisolated struct BandClockTime: Codable, Equatable, Hashable {
    var hour: Int
    var minute: Int
}

/// The band settings Anew Link can change, in plain values so they can be saved and tested.
///
/// Every field and value comes from our own captures of Sony's app (spec 15.2 and 15.5).
/// The band can't be read back, so these values are what Anew Link last sent (or the defaults
/// below, which are a typical band's settings, until the user changes something).
nonisolated struct BandSettings: Codable, Equatable {

    enum Strength: Int, Codable, CaseIterable, Identifiable {
        case normal = 0, weak = 1, strong = 2
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .weak: "Weak"
            case .normal: "Medium"
            case .strong: "Strong"
            }
        }
        /// In the order Sony's app lists them.
        static let ordered: [Strength] = [.weak, .normal, .strong]
    }

    // Vibration (0x08)
    var vibration: Strength = .normal
    var stopVibratingAtRest = false

    // Disconnection alert (0x09)
    var disconnectAlertOn = false
    /// Sent in 5-second steps, so it must be a multiple of 5 (see `disconnectDelayChoices`).
    var disconnectAlertSeconds = 5

    // Do not disturb (0x14)
    var doNotDisturbOn = false
    var doNotDisturbStart = BandClockTime(hour: 0, minute: 0)
    var doNotDisturbEnd = BandClockTime(hour: 6, minute: 0)

    // Auto power off (0x15)
    var autoPowerOffOn = false
    var autoPowerOffStart = BandClockTime(hour: 22, minute: 0)
    var autoPowerOffEnd = BandClockTime(hour: 8, minute: 0)

    // Day start (0x16)
    var dayStartHour = 0

    // Step goal (0x17)
    var goalNotification = true
    var stepGoal = 6000

    // Display (0x1A). The band takes all display fields at once.
    var leftWrist = true
    var largeFont = false
    /// Language: 0 English, 1 Japanese.
    var japanese = false
    var raiseToWake = true
    var richHomeDesign = false
    /// Sony's app sent 0 here; weather in the status bar is not offered in the UI.
    var weatherInStatusBar = false
    /// Sony's app sent 7 seconds; only that value has been seen, so the UI doesn't change it.
    var displaySeconds = 7

    // Home screen icons (0x1B)
    var homeLeft: HomeIcon = .stress
    var homeCentre: HomeIcon = .heartRate
    var homeRight: HomeIcon = .steps

    // Hardware button (0x1C)
    var longPress: ButtonAction = .weatherScreen
    var doublePress: ButtonAction = .timerScreen

    /// Delays seen in Sony's picker, in seconds (all multiples of 5).
    static let disconnectDelayChoices = [5, 10, 15, 30, 60, 120, 180, 240]
}

/// Home screen icon ids (spec 15.5). Only icons that still work without Sony's servers.
nonisolated enum HomeIcon: Int, Codable, CaseIterable, Identifiable {
    case timer = 0x01, alarm = 0x02, clock = 0x03, edyBalance = 0x07, schedule = 0x09
    case steps = 0x0A, sleep = 0x0B, heartRate = 0x0C, vo2Max = 0x0D, stress = 0x0E
    case bodyEnergy = 0x0F, suicaBalance = 0x10, calorie = 0x11, music = 0x13, camera = 0x14

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .timer: "Timer"
        case .alarm: "Alarm"
        case .clock: "Clock"
        case .edyBalance: "Edy balance"
        case .schedule: "Schedule"
        case .steps: "Steps"
        case .sleep: "Sleep"
        case .heartRate: "Heart rate"
        case .vo2Max: "VO2 Max"
        case .stress: "Stress & Recovery"
        case .bodyEnergy: "Body Energy"
        case .suicaBalance: "Suica balance"
        case .calorie: "Calories"
        case .music: "Music"
        case .camera: "Camera"
        }
    }
}

/// Hardware button action codes (spec 15.5; the same codes as Head Linkage, section 12).
/// Alexa, Qrio Lock and Riiiver are left out: they needed services that have ended.
nonisolated enum ButtonAction: UInt16, Codable, CaseIterable, Identifiable {
    case none = 0x0000
    case findPhone = 0x0300
    case nfcToggle = 0x0400
    case doNotDisturbToggle = 0x0500
    case timerScreen = 0x0600
    case weatherScreen = 0x0700
    case musicScreen = 0x1000
    case musicPlayPause = 0x1001
    case musicNext = 0x1002
    case musicPrevious = 0x1003

    var id: UInt16 { rawValue }

    /// On the wire: the high byte first, then the low byte (for example `07 00` = weather screen).
    var bytes: [UInt8] { [UInt8(rawValue >> 8), UInt8(rawValue & 0xFF)] }

    var label: String {
        switch self {
        case .none: "Nothing"
        case .findPhone: "Find your phone"
        case .nfcToggle: "NFC on or off"
        case .doNotDisturbToggle: "Do not disturb on or off"
        case .timerScreen: "Timer screen"
        case .weatherScreen: "Weather screen"
        case .musicScreen: "Music screen"
        case .musicPlayPause: "Music play or pause"
        case .musicNext: "Music next track"
        case .musicPrevious: "Music previous track"
        }
    }
}

/// Builds the settings packets for the control characteristic 1514.
///
/// Each one matches byte for byte what Sony's app sent for the same setting (spec 15.2, 15.5).
/// Deliberately missing: `0x12` (notification and calendar toggles), `0x1D` (body details),
/// `0x18`/`0x19` (page order) and anything `0xC0` (Head Linkage).
nonisolated enum WenaSettings {

    /// The groups the settings screen changes. Each is sent on its own, like Sony's app does.
    enum Group: String, Codable, CaseIterable {
        case vibration, disconnectAlert, doNotDisturb, autoPowerOff, dayStart, stepGoal, display, homeIcons, buttons
    }

    /// The packets for one group, in order.
    static func packets(for group: Group, _ s: BandSettings) -> [Data] {
        switch group {
        case .vibration: [vibration(s)]
        case .disconnectAlert: [disconnectAlert(s)]
        case .doNotDisturb: [doNotDisturb(s)]
        case .autoPowerOff: [autoPowerOff(s)]
        case .dayStart: [dayStart(s)]
        case .stepGoal: [stepGoal(s)]
        case .display: [display(s)]
        // Sony's app always re-sends the display packet just before the home icons.
        case .homeIcons: [display(s), homeIcons(s)]
        case .buttons: [buttons(s)]
        }
    }

    /// Every group, for "Send all settings". The home icons already include the display packet.
    static func allPackets(_ s: BandSettings) -> [Data] {
        Group.allCases.filter { $0 != .display }.flatMap { packets(for: $0, s) }
    }

    /// `08`, strength (0 medium, 1 weak, 2 strong), stop at rest (1/0).
    static func vibration(_ s: BandSettings) -> Data {
        Data([0x08, UInt8(s.vibration.rawValue), s.stopVibratingAtRest ? 1 : 0])
    }

    /// `09`, 0 for off, otherwise the delay in 5-second steps (`09 18` = 2 minutes).
    static func disconnectAlert(_ s: BandSettings) -> Data {
        guard s.disconnectAlertOn else { return Data([0x09, 0x00]) }
        let steps = min(max(s.disconnectAlertSeconds / 5, 1), 255)
        return Data([0x09, UInt8(steps)])
    }

    /// `14`, on (1/0), start hour, start minute, end hour, end minute.
    static func doNotDisturb(_ s: BandSettings) -> Data {
        window(0x14, on: s.doNotDisturbOn, s.doNotDisturbStart, s.doNotDisturbEnd)
    }

    /// `15`, same layout as do not disturb.
    static func autoPowerOff(_ s: BandSettings) -> Data {
        window(0x15, on: s.autoPowerOffOn, s.autoPowerOffStart, s.autoPowerOffEnd)
    }

    /// `16`, the hour the band's day starts.
    static func dayStart(_ s: BandSettings) -> Data {
        Data([0x16, UInt8(clamping: min(max(s.dayStartHour, 0), 23))])
    }

    /// `17`, goal notification (1/0), steps (int32, little-endian).
    static func stepGoal(_ s: BandSettings) -> Data {
        var data = Data([0x17, s.goalNotification ? 1 : 0])
        withUnsafeBytes(of: Int32(clamping: max(s.stepGoal, 0)).littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    /// `1A`, font (0 normal, 1 large), wrist (0 right, 1 left), language (0 English, 1 Japanese),
    /// raise to wake, design (0 normal, 1 rich), weather in status bar, display seconds.
    static func display(_ s: BandSettings) -> Data {
        Data([0x1A,
              s.largeFont ? 1 : 0,
              s.leftWrist ? 1 : 0,
              s.japanese ? 1 : 0,
              s.raiseToWake ? 1 : 0,
              s.richHomeDesign ? 1 : 0,
              s.weatherInStatusBar ? 1 : 0,
              UInt8(clamping: s.displaySeconds)])
    }

    /// `1B`, left, centre, right: each `00` then the icon id.
    static func homeIcons(_ s: BandSettings) -> Data {
        Data([0x1B, 0x00, UInt8(s.homeLeft.rawValue), 0x00, UInt8(s.homeCentre.rawValue), 0x00, UInt8(s.homeRight.rawValue)])
    }

    /// `1C`, long press action, double press action (2 bytes each).
    static func buttons(_ s: BandSettings) -> Data {
        Data([0x1C] + s.longPress.bytes + s.doublePress.bytes)
    }

    private static func window(_ opcode: UInt8, on: Bool, _ start: BandClockTime, _ end: BandClockTime) -> Data {
        Data([opcode, on ? 1 : 0,
              UInt8(clamping: start.hour), UInt8(clamping: start.minute),
              UInt8(clamping: end.hour), UInt8(clamping: end.minute)])
    }
}

/// The one-off test notification, as sent by Sony's "Try this notification pattern" button
/// (spec section 8 layout, confirmed on our band in 15.5). Written to 4002.
///
/// This is not notification forwarding: iOS delivers real notifications through ANCS.
/// It only lets the user feel the current vibration strength.
nonisolated enum WenaTestNotification {

    /// LED colour white, vibration flags 03, pattern basic, vibrate once.
    static let white: UInt8 = 0x07
    static let basicPattern: UInt8 = 0x02

    static let title = "Anew Link"
    static let message = "Vibration test"

    /// `00`, colour, `03`, pattern, count, title length, message length, flags `01`, kind `00`,
    /// action length `00`, notification id (int32), Wena timestamp (int32), title, message.
    /// The colour, pattern and count default to white, basic, once; the notification list's
    /// "Try it" button passes the app's own choices.
    static func packet(id: Int32, date: Date, colour: UInt8 = white, pattern: UInt8 = basicPattern,
                       count: UInt8 = 0x01, text: String = message) -> Data {
        let titleBytes = Array(title.utf8.prefix(31))
        let messageBytes = Array(text.utf8.prefix(239))
        var data = Data([0x00, colour, 0x03, pattern, count,
                         UInt8(titleBytes.count), UInt8(messageBytes.count), 0x01, 0x00, 0x00])
        withUnsafeBytes(of: id.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: WenaPackets.wenaTimestamp(for: date).littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: titleBytes)
        data.append(contentsOf: messageBytes)
        return data
    }
}
