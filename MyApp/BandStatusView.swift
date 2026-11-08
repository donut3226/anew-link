import SwiftUI

/// The first screen: finds the band and shows its firmware, battery and serial.
///
/// This view owns the Bluetooth object and starts or stops it.
/// The drawing itself happens in `BandStatusContent` below, which only takes plain values,
/// so previews can show every state with fake data and no Bluetooth.
struct BandStatusView: View {
    // @State keeps the same BandConnection alive while this screen is on display.
    @State private var connection = BandConnection()
    @State private var weatherSync = WeatherSync()
    @State private var healthSync = HealthSync()

    var body: some View {
        BandStatusContent(
            state: connection.state,
            info: connection.info,
            batteryPercent: connection.batteryPercent,
            timeSync: connection.timeSync,
            weather: weatherSync.status,
            activity: connection.activity,
            rawActivityHex: Self.hex(connection.rawActivityPackets),
            health: healthSync.status,
            isBusy: connection.isSending || weatherSync.isBusy || connection.activity.inProgress || healthSync.isBusy,
            onRefresh: { connection.refresh() },
            onSyncTime: { offset in connection.syncTime(offsetSeconds: offset) },
            // Task { } starts async work (location, then internet) without blocking the screen.
            onSendWeather: { Task { await weatherSync.sendForecast(using: connection) } },
            onSendTestWeather: { weatherSync.sendTestPattern(using: connection) },
            onSyncActivity: { connection.syncActivity() },
            onSaveToHealth: {
                guard case .done(let result) = connection.activity else { return }
                let firmware = connection.info?.firmwareName
                Task { await healthSync.save(result.samples, firmware: firmware) }
            }
        )
        .onAppear { connection.start() }
        .onDisappear { connection.stop() }
    }

    /// One packet per line, as hex bytes, for the debug share button.
    private static func hex(_ packets: [Data]) -> String {
        packets
            .map { packet in packet.map { String(format: "%02X", $0) }.joined(separator: " ") }
            .joined(separator: "\n")
    }
}

struct BandStatusContent: View {
    let state: BandConnection.State
    let info: BandInfo?
    let batteryPercent: Int?
    var timeSync: BandConnection.TimeSyncStatus = .idle
    var weather: WeatherSync.Status = .idle
    var activity: BandConnection.ActivityStatus = .idle
    /// Raw activity packets as hex text (debug share button only).
    var rawActivityHex = ""
    var health: HealthSync.Status = .idle
    /// True while anything is being sent, so only one send runs at a time.
    var isBusy = false
    let onRefresh: () -> Void
    /// Called with how many seconds to add to the time sent: 0 normally, 300 for the debug test.
    var onSyncTime: (TimeInterval) -> Void = { _ in }
    var onSendWeather: () -> Void = {}
    var onSendTestWeather: () -> Void = {}
    var onSyncActivity: () -> Void = {}
    var onSaveToHealth: () -> Void = {}

    // Hidden by default so the serial doesn't end up in screenshots.
    @State private var showSerial = false

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    statusRow
                }

                if state == .connected {
                    Section("Band") {
                        LabeledContent("Firmware", value: info?.firmwareName ?? "Reading…")
                        LabeledContent("Battery", value: batteryPercent.map { "\($0)%" } ?? "Reading…")
                        serialRow
                    }

                    Section("Time") {
                        Button("Sync time") { onSyncTime(0) }
                            .disabled(isBusy)
                        timeSyncRow
                    }

                    Section {
                        Button("Send weather", action: onSendWeather)
                            .disabled(isBusy)
                        weatherRow
                    } header: {
                        Text("Weather")
                    } footer: {
                        Text("Uses your approximate location. Weather data by Open-Meteo.com")
                    }

                    Section {
                        Button("Sync activity (last 24 h)", action: onSyncActivity)
                            .disabled(isBusy || info?.supportsActivitySync == false)
                        activityRows
                    } header: {
                        Text("Activity")
                    } footer: {
                        switch info?.supportsActivitySync {
                        case false?:
                            Text("Activity sync needs band firmware 2.40 or later.")
                        case nil:
                            Text("Couldn't read the firmware version. Activity sync needs 2.40 or later.")
                        case true?:
                            Text("Steps and heart rate, read from the band. Not saved anywhere yet.")
                        }
                    }

                    // #if DEBUG: this section only exists in builds run from Xcode,
                    // never in App Store builds.
                    #if DEBUG
                    Section {
                        Button("Test: set band 5 min fast") { onSyncTime(5 * 60) }
                            .disabled(isBusy)
                        Button("Test: send test weather", action: onSendTestWeather)
                            .disabled(isBusy)
                        if !rawActivityHex.isEmpty {
                            ShareLink("Share raw activity packets", item: rawActivityHex)
                        }
                    } header: {
                        Text("Debug only")
                    } footer: {
                        Text("5 min fast: tap Sync time afterwards to put the band's clock right. Test weather: 5 days of sunny 25, cloudy 20, rain 15, heavy rain 10 and snow 0 C maximums.")
                    }
                    #endif
                }

                if let buttonTitle {
                    Section {
                        Button(buttonTitle, action: onRefresh)
                    }
                }
            }
            .navigationTitle("Buckle Link")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch state {
        case .starting:
            busyRow("Starting Bluetooth…")
        case .unsupported:
            Label("Bluetooth isn't available on this device. Run the app on your iPhone.",
                  systemImage: "antenna.radiowaves.left.and.right.slash")
        case .unauthorized:
            Label("Bluetooth permission is off. Turn it on in Settings > Privacy & Security > Bluetooth.",
                  systemImage: "hand.raised")
        case .poweredOff:
            Label("Bluetooth is turned off.", systemImage: "antenna.radiowaves.left.and.right.slash")
        case .searching:
            busyRow("Looking for your band…")
        case .notFound:
            Label("Band not found. Keep it nearby with its screen on, and check it shows as Connected in Settings > Bluetooth.",
                  systemImage: "questionmark.circle")
        case .connecting:
            busyRow("Connecting…")
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var serialRow: some View {
        if let info {
            if showSerial {
                LabeledContent("Serial", value: String(info.serialNumber))
                    .privacySensitive()
                    .onTapGesture { showSerial = false }
            } else {
                Button("Show serial") { showSerial = true }
            }
        }
    }

    @ViewBuilder
    private var timeSyncRow: some View {
        switch timeSync {
        case .idle:
            EmptyView()
        case .sending:
            busyRow("Syncing time…")
        case .done(let at, let wasTest, let timeZoneSkipped):
            VStack(alignment: .leading, spacing: 4) {
                Label(wasTest
                      ? "Test sent at \(at.formatted(date: .omitted, time: .shortened)): band should be 5 min fast"
                      : "Time synced at \(at.formatted(date: .omitted, time: .shortened))",
                      systemImage: wasTest ? "testtube.2" : "checkmark.circle.fill")
                    .foregroundStyle(wasTest ? .orange : .green)
                if timeZoneSkipped {
                    Text("Time zone not sent: the band's handling of your zone isn't verified yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var weatherRow: some View {
        switch weather {
        case .idle:
            EmptyView()
        case .locating:
            busyRow("Finding your location…")
        case .fetching:
            busyRow("Getting the forecast…")
        case .sending:
            busyRow("Sending to the band…")
        case .done(let today, let at):
            let time = at.formatted(date: .omitted, time: .shortened)
            if let today {
                Label("Sent at \(time). Today: \(Self.describe(today.wenaDay)), \(Self.degrees(today.minCelsius)) to \(Self.degrees(today.maxCelsius))",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Test weather sent at \(time)", systemImage: "testtube.2")
                    .foregroundStyle(.orange)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var activityRows: some View {
        switch activity {
        case .idle:
            EmptyView()
        case .subscribing:
            busyRow("Asking the band for activity data…")
        case .receiving(let packets):
            busyRow("Receiving… \(packets) packets")
        case .done(let result):
            let summary = result.summary
            LabeledContent("Steps today", value: "\(summary.stepsToday)")
            LabeledContent("Steps, last 24 h", value: "\(summary.stepsLast24Hours)")
            LabeledContent("Heart rate", value: summary.latestHeartRate.map { bpm in
                "\(bpm) bpm at \(Self.clock(summary.latestHeartRateAt))"
            } ?? "No readings")
            if let low = summary.heartRateMin, let high = summary.heartRateMax {
                LabeledContent("Heart rate range", value: "\(low)-\(high) bpm")
            }
            LabeledContent("Newest sample", value: Self.newestSampleText(summary))
            #if DEBUG
            LabeledContent("Packets",
                           value: "\(result.packetCount), \(result.badCRCCount) CRC errors, \(result.receivedFinish ? "finished" : "timed out")")
            #endif
            Button("Save to Apple Health", action: onSaveToHealth)
                .disabled(isBusy)
            healthRow
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var healthRow: some View {
        switch health {
        case .idle:
            EmptyView()
        case .asking:
            busyRow("Waiting for Health permission…")
        case .saving:
            busyRow("Saving to Health…")
        case .done(let steps, let heartRates, let notAllowed):
            VStack(alignment: .leading, spacing: 4) {
                Label("Saved \(steps) step minutes and \(heartRates) heart-rate readings",
                      systemImage: "heart.circle.fill")
                    .foregroundStyle(.green)
                if notAllowed > 0 {
                    Text("\(notAllowed) not saved: that type isn't allowed in Health > Profile > Apps > Buckle Link.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    /// "14:32 (2 min before sync)". If the band's clock is ahead, the sample can be "after" the sync.
    private static func newestSampleText(_ summary: ActivitySummary) -> String {
        guard let newest = summary.newestSampleAt, let minutes = summary.newestSampleMinutesAgo else {
            return "None"
        }
        let when = minutes >= 0 ? "\(minutes) min before sync" : "\(-minutes) min after sync"
        return "\(clock(newest)) (\(when))"
    }

    private static func clock(_ date: Date?) -> String {
        date?.formatted(date: .omitted, time: .shortened) ?? "?"
    }

    /// Plain-words name for what the band will show, for example "sunny with cloud".
    private static func describe(_ day: WenaWeatherDay) -> String {
        func name(_ condition: WenaCondition) -> String {
            switch condition {
            case .sunny: "sunny"
            case .cloudy: "cloudy"
            case .rain: "rain"
            case .heavyRain: "heavy rain"
            case .snow: "snow"
            }
        }
        return day.main == day.sub ? name(day.main) : "\(name(day.main)) / \(name(day.sub))"
    }

    private static func degrees(_ celsius: Double) -> String {
        "\(Int(celsius.rounded())) C"
    }

    private func busyRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
        }
    }

    /// Which button to show, if any, for the current state.
    private var buttonTitle: String? {
        switch state {
        case .connected: "Refresh"
        case .notFound, .failed: "Try again"
        default: nil
        }
    }
}

// Previews use obviously fake values. Never put the real band's serial here.

#Preview("Connected") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      onRefresh: {})
}

#Preview("Time synced") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      timeSync: .done(at: .now, wasTest: false, timeZoneSkipped: false),
                      onRefresh: {})
}

#Preview("Time test sent") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      timeSync: .done(at: .now, wasTest: true, timeZoneSkipped: true),
                      onRefresh: {})
}

#Preview("Time sync failed") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      timeSync: .failed("The band didn't accept the time."),
                      onRefresh: {})
}

#Preview("Weather sent") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      weather: .done(today: DailyForecast(day: "2026-01-01", weatherCode: 2,
                                                          minCelsius: 12, maxCelsius: 21),
                                     at: .now),
                      onRefresh: {})
}

#Preview("Weather busy") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      weather: .fetching,
                      isBusy: true,
                      onRefresh: {})
}

#Preview("Activity synced") {
    let now = Date.now
    let samples = (0..<60).map { minute in
        ActivitySample(type: minute.isMultiple(of: 2) ? .steps : .heartRate,
                       date: now.addingTimeInterval(TimeInterval(-3600 + minute * 60)),
                       value: minute.isMultiple(of: 2) ? 40 : 70)
    }
    return BandStatusContent(
        state: .connected,
        info: BandInfo(firmwareName: "2.40PR", serialNumber: 0),
        batteryPercent: 80,
        activity: .done(.init(summary: ActivitySummary(samples: samples, now: now), samples: samples,
                              syncedAt: now, packetCount: 42, badCRCCount: 0, receivedFinish: true)),
        health: .done(steps: 30, heartRates: 30, notAllowed: 0),
        onRefresh: {})
}

#Preview("Old firmware") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "2.30PR", serialNumber: 0),
                      batteryPercent: 80,
                      onRefresh: {})
}

#Preview("Searching") {
    BandStatusContent(state: .searching, info: nil, batteryPercent: nil, onRefresh: {})
}

#Preview("Not found") {
    BandStatusContent(state: .notFound, info: nil, batteryPercent: nil, onRefresh: {})
}

#Preview("Failed") {
    BandStatusContent(state: .failed("Lost the connection to the band."),
                      info: nil, batteryPercent: nil, onRefresh: {})
}
