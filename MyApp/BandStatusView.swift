import SwiftUI

/// The first screen: shows the band's firmware, battery and serial, and the send buttons.
///
/// The Bluetooth object and the sync objects live in `AppServices` (created at launch);
/// this view only shows them.
/// The drawing itself happens in `BandStatusContent` below, which only takes plain values,
/// so previews can show every state with fake data and no Bluetooth.
struct BandStatusView: View {
    let services: AppServices
    private var connection: BandConnection { services.connection }
    private var weatherSync: WeatherSync { services.weatherSync }
    private var autoSync: AutoSync { services.autoSync }
    private var healthSync: HealthSync { services.healthSync }
    private var nowPlaying: NowPlayingSync { services.nowPlaying }
    private var activityAutoSync: ActivityAutoSync { services.activityAutoSync }
    private var findPhone: FindPhone { services.findPhone }
    private var calendarSync: CalendarSync { services.calendarSync }
    private var alarmStore: AlarmStore { services.alarmStore }
    private var bandSettings: BandSettingsStore { services.bandSettings }
    private var notificationApps: NotificationAppsStore { services.notificationApps }
    /// The "Show calendar on band" switch.
    @AppStorage(CalendarSync.enabledKey) private var showCalendar = false
    /// Demo mode (made-up data, no band). Not saved: the app always starts live.
    @State private var isDemo = false
    /// The "Ring when the band looks for this phone" switch.
    @AppStorage(FindPhone.enabledKey) private var findPhoneEnabled = false
    /// The "Save activity to Apple Health automatically" switch.
    @AppStorage(ActivityAutoSync.enabledKey) private var autoSaveActivity = true
    /// The "update automatically" switch, saved in the iPhone's settings store.
    @AppStorage(AutoSync.enabledKey) private var autoUpdate = true
    /// Whether the app is on screen, in the background, or between the two.
    @Environment(\.scenePhase) private var scenePhase
    /// The "Show song title on band" switch.
    @AppStorage(NowPlayingSync.enabledKey) private var showSongTitle = false

    var body: some View {
        Group {
            if isDemo {
                DemoView(onExit: { isDemo = false })
            } else {
                liveContent
            }
        }
        // While the phone rings with the app open, an alert over everything, so "Found it"
        // is always one tap away (iOS shows no notification while the app is on screen).
        .alert("Your band is looking for this phone", isPresented: Binding(
            get: { findPhone.isRinging },
            set: { showing in if !showing { findPhone.stop() } }
        )) {
            Button("Found it") { findPhone.stop() }
        }
        .onChange(of: showCalendar) {
            Task { await calendarSync.enabledChanged(connection: connection) }
        }
        .onChange(of: findPhoneEnabled) {
            Task { await findPhone.enabledChanged() }
        }
        .onChange(of: showSongTitle) {
            Task { await nowPlaying.enabledChanged() }
        }
        // Automatic updates: when the band connects, and when the app comes back on screen.
        // AutoSync itself checks the switch and whether an update is actually due.
        .onChange(of: connection.state) { _, newState in
            if newState == .connected { runAutoSync() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { runAutoSync() }
        }
    }

    /// The real screen, driven by the band connection.
    private var liveContent: some View {
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
            autoUpdate: $autoUpdate,
            lastAutoUpdate: autoSync.lastUpdate,
            // Task { } starts async work (Bluetooth, location, internet) without blocking the screen.
            onSyncTime: { offset in Task { await connection.syncTime(offsetSeconds: offset) } },
            onSendWeather: { Task { await weatherSync.sendForecast(using: connection) } },
            onSendTestWeather: { Task { await weatherSync.sendTestPattern(using: connection) } },
            onSyncActivity: { connection.syncActivity() },
            onSaveToHealth: {
                guard case .done(let result) = connection.activity else { return }
                let firmware = connection.info?.firmwareName
                Task {
                    // A full 24-hour save also counts for the automatic sync's starting point.
                    if await healthSync.save(result.samples, firmware: firmware) {
                        activityAutoSync.recordSave(syncedAt: result.syncedAt)
                    }
                }
            },
            autoSaveActivity: $autoSaveActivity,
            lastActivitySave: activityAutoSync.lastSave,
            eventLog: connection.events,
            isListeningForRequests: connection.isListeningForRequests,
            showSongTitle: $showSongTitle,
            music: nowPlaying.status,
            musicPermissionDenied: nowPlaying.permissionDenied,
            onSendTestMusic: { Task { await nowPlaying.sendTest() } },
            findPhoneEnabled: $findPhoneEnabled,
            findPhoneRinging: findPhone.isRinging,
            findPhoneLastRequest: findPhone.lastRequest,
            findPhonePermissionDenied: findPhone.permissionDenied,
            onStopRinging: { findPhone.stop() },
            onTestFindPhone: { Task { _ = await findPhone.bandAsked() } },
            showCalendar: $showCalendar,
            calendar: calendarSync.status,
            calendarPermissionDenied: calendarSync.permissionDenied,
            onSendTestCalendar: { Task { await calendarSync.sendTest(using: connection) } },
            alarms: alarmStore.alarms,
            alarmStatus: alarmStore.status,
            canAddAlarm: alarmStore.canAdd,
            onSaveAlarm: { alarm in Task { await alarmStore.save(alarm, using: connection) } },
            onToggleAlarm: { id, isOn in Task { await alarmStore.setOn(isOn, for: id, using: connection) } },
            onDeleteAlarm: { id in Task { await alarmStore.delete(id, using: connection) } },
            bandSettings: bandSettings.settings,
            bandSettingsStatus: bandSettings.status,
            onChangeBandSettings: { new in Task { await bandSettings.update(new, using: connection) } },
            onSendAllBandSettings: {
                Task {
                    await bandSettings.sendAll(using: connection)
                    await notificationApps.sendAll(using: connection)
                }
            },
            onTestVibration: { Task { await bandSettings.testVibration(using: connection) } },
            notificationApps: notificationApps.apps,
            notificationStatus: notificationApps.status,
            notificationListFound: connection.state != .connected || connection.notificationListUUID != nil,
            notificationNeverSent: notificationApps.neverSent,
            onChangeNotificationApps: { list in Task { await notificationApps.update(list, using: connection) } },
            onTryNotification: { app in Task { await bandSettings.testVibration(using: connection, app: app) } },
            onStartDemo: { isDemo = true }
        )
    }

    private func runAutoSync() {
        Task {
            // A short pause so the band's weather characteristic is found before we use it.
            try? await Task.sleep(for: .seconds(1))
            // Alarm changes made while the band was away go first (they were user actions).
            if let outcome = await alarmStore.sendIfPending(using: connection) {
                connection.events.add(BandEvent(date: Date(), kind: .info, detail: outcome))
            }
            if let outcome = await bandSettings.sendIfPending(using: connection) {
                connection.events.add(BandEvent(date: Date(), kind: .info, detail: outcome))
            }
            if let outcome = await notificationApps.sendIfPending(using: connection) {
                connection.events.add(BandEvent(date: Date(), kind: .info, detail: outcome))
            }
            await autoSync.runIfDue(connection: connection, weather: weatherSync)
            // Then activity, if 2 hours have passed (each checks its own switch and timing).
            await activityAutoSync.runIfDue(connection: connection, health: healthSync)
        }
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
    /// A Binding lets this view change a value owned by its parent (the switch's on/off).
    var autoUpdate: Binding<Bool> = .constant(true)
    var lastAutoUpdate: Date?
    var onSyncTime: (TimeInterval) -> Void = { _ in }
    var onSendWeather: () -> Void = {}
    var onSendTestWeather: () -> Void = {}
    var onSyncActivity: () -> Void = {}
    var onSaveToHealth: () -> Void = {}
    var autoSaveActivity: Binding<Bool> = .constant(true)
    var lastActivitySave: Date?
    /// The band request log (debug section only). nil in previews.
    var eventLog: BandEventLog?
    var isListeningForRequests = false
    var showSongTitle: Binding<Bool> = .constant(false)
    var music: NowPlayingSync.Status = .idle
    var musicPermissionDenied = false
    var onSendTestMusic: () -> Void = {}
    var findPhoneEnabled: Binding<Bool> = .constant(false)
    var findPhoneRinging = false
    var findPhoneLastRequest: Date?
    var findPhonePermissionDenied = false
    var onStopRinging: () -> Void = {}
    var onTestFindPhone: () -> Void = {}
    var showCalendar: Binding<Bool> = .constant(false)
    var calendar: CalendarSync.Status = .idle
    var calendarPermissionDenied = false
    var onSendTestCalendar: () -> Void = {}
    var alarms: [BandAlarm] = []
    var alarmStatus: AlarmStore.Status = .idle
    var canAddAlarm = true
    var onSaveAlarm: (BandAlarm) -> Void = { _ in }
    var onToggleAlarm: (BandAlarm.ID, Bool) -> Void = { _, _ in }
    var onDeleteAlarm: (BandAlarm.ID) -> Void = { _ in }
    var bandSettings = BandSettings()
    var bandSettingsStatus: BandSettingsStore.Status = .idle
    var onChangeBandSettings: (BandSettings) -> Void = { _ in }
    var onSendAllBandSettings: () -> Void = {}
    var onTestVibration: () -> Void = {}
    var notificationApps: [NotifyApp] = WenaNotificationList.defaultList()
    var notificationStatus: NotificationAppsStore.Status = .idle
    var notificationListFound = true
    var notificationNeverSent = false
    var onChangeNotificationApps: ([NotifyApp]) -> Void = { _ in }
    var onTryNotification: (NotifyApp) -> Void = { _ in }
    /// Shown as "Try the demo" when there's no band to talk to (nil hides it).
    var onStartDemo: (() -> Void)?
    /// Demo mode only: shows the demo banner with an Exit button.
    var onExitDemo: (() -> Void)?

    // Hidden by default so the serial doesn't end up in screenshots.
    @State private var showSerial = false
    /// The alarm open in the editor (a new one has an id not yet in `alarms`).
    @State private var editingAlarm: BandAlarm?

    var body: some View {
        NavigationStack {
            List {
                if let onExitDemo {
                    Section {
                        Label("Demo mode: made-up data, no band connected. Nothing is sent or saved.",
                              systemImage: "play.rectangle")
                        Button("Exit demo", action: onExitDemo)
                    }
                }

                Section("Status") {
                    statusRow
                }

                if let onStartDemo, canStartDemo {
                    Section {
                        Button("Try the demo", action: onStartDemo)
                    } footer: {
                        Text("No band nearby? The demo shows every feature with made-up data.")
                    }
                }

                if state == .connected {
                    Section("Band") {
                        LabeledContent("Firmware", value: info?.firmwareName ?? "Reading…")
                        LabeledContent("Battery", value: batteryPercent.map { "\($0)%" } ?? "Reading…")
                        serialRow
                    }

                    Section {
                        Toggle("Update weather and time automatically", isOn: autoUpdate)
                        LabeledContent("Last automatic update",
                                       value: lastAutoUpdate.map { Self.dayAndTime($0) } ?? "Not yet")
                    } header: {
                        Text("Automatic updates")
                    } footer: {
                        Text("Sends the time and weather when the band asks (at most every 2 hours) and when the app opens if the forecast is over 3 hours old, from yesterday, or you've changed time zone.")
                    }

                    Section("Time") {
                        Button("Sync time") { onSyncTime(0) }
                            .disabled(isBusy)
                        timeSyncRow
                    }

                    Section {
                        Toggle("Show song title on band", isOn: showSongTitle)
                        musicRow
                    } header: {
                        Text("Music")
                    } footer: {
                        Text("Shows the song playing in Apple Music when you open the band's music screen. The band's play, skip and volume buttons work through iOS already.")
                    }

                    Section {
                        Toggle("Show calendar on band", isOn: showCalendar)
                        calendarRow
                    } header: {
                        Text("Calendar")
                    } footer: {
                        Text("Sends the next 7 days of events (up to 30) when the band asks, about once an hour. Read-only: your calendar is never changed.")
                    }

                    Section {
                        ForEach(alarms) { alarm in
                            alarmRow(alarm)
                        }
                        .onDelete { offsets in
                            offsets.map { alarms[$0].id }.forEach(onDeleteAlarm)
                        }
                        if canAddAlarm {
                            Button("Add alarm") { editingAlarm = BandAlarm() }
                        }
                        alarmStatusRow
                    } header: {
                        Text("Alarms")
                    } footer: {
                        Text("Vibrating alarms on the band, up to 9. Changes are sent straight away and replace all alarms on the band.")
                    }

                    Section {
                        NavigationLink {
                            BandSettingsView(settings: bandSettings, status: bandSettingsStatus, isBusy: isBusy,
                                             onChange: onChangeBandSettings, onSendAll: onSendAllBandSettings,
                                             onTestVibration: onTestVibration)
                        } label: {
                            Label("Band settings", systemImage: "slider.horizontal.3")
                        }
                        NavigationLink {
                            NotificationAppsView(apps: notificationApps, status: notificationStatus, isBusy: isBusy,
                                                 listFound: notificationListFound, neverSent: notificationNeverSent,
                                                 onChange: onChangeNotificationApps, onTry: onTryNotification)
                        } label: {
                            Label("Notifications on the band", systemImage: "bell.badge")
                        }
                    } footer: {
                        Text("Vibration, display, home screen, button, step goal and quiet times, and which apps' notifications reach the band.")
                    }

                    Section {
                        Toggle("Ring when the band looks for this phone", isOn: findPhoneEnabled)
                        if findPhoneRinging {
                            Button("Found it", action: onStopRinging)
                                .font(.headline)
                        }
                        if findPhonePermissionDenied {
                            Label("Notifications are off. Turn them on in Settings > Notifications > Anew Link.",
                                  systemImage: "hand.raised")
                                .foregroundStyle(.orange)
                        } else if let findPhoneLastRequest {
                            LabeledContent("Band last asked", value: Self.clock(findPhoneLastRequest))
                        }
                    } header: {
                        Text("Find my phone")
                    } footer: {
                        Text("With the app open, it rings at your media volume and vibrates, even in silent mode. Otherwise it shows a notification, which follows your ringer and silent mode.")
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
                        Toggle("Save to Apple Health automatically", isOn: autoSaveActivity)
                        LabeledContent("Last saved",
                                       value: lastActivitySave.map { Self.dayAndTime($0) } ?? "Not yet")
                    } header: {
                        Text("Activity")
                    } footer: {
                        switch info?.supportsActivitySync {
                        case false?:
                            Text("Activity sync needs band firmware 2.40 or later.")
                        case nil:
                            Text("Couldn't read the firmware version. Activity sync needs 2.40 or later.")
                        case true?:
                            Text("Steps and heart rate, read from the band. Saved automatically about every 2 hours, also with the phone locked, after you've tapped Save to Apple Health once to allow it.")
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
                        Button("Test: send music text", action: onSendTestMusic)
                            .disabled(isBusy)
                        Button("Test: find my phone", action: onTestFindPhone)
                        Button("Test: send test calendar", action: onSendTestCalendar)
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

                AppIconSection()

                #if DEBUG
                if let eventLog {
                    bandRequestsSection(eventLog)
                }
                #endif

                if let buttonTitle {
                    Section {
                        Button(buttonTitle, action: onRefresh)
                    }
                }
            }
            .navigationTitle("Anew Link")
            .sheet(item: $editingAlarm) { alarm in
                let isNew = !alarms.contains { $0.id == alarm.id }
                AlarmEditor(alarm: alarm, isNew: isNew,
                            onSave: { onSaveAlarm($0); editingAlarm = nil },
                            onDelete: { onDeleteAlarm(alarm.id); editingAlarm = nil },
                            onCancel: { editingAlarm = nil })
            }
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
        case .reconnecting:
            busyRow("Reconnecting… (waiting for the band to come back in range)")
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
        case .done(let at, let wasTest, let timeZoneSkipped, let automatic):
            VStack(alignment: .leading, spacing: 4) {
                Label(wasTest
                      ? "Test sent at \(at.formatted(date: .omitted, time: .shortened)): band should be 5 min fast"
                      : "Time synced at \(at.formatted(date: .omitted, time: .shortened))\(automatic ? " (automatic)" : "")",
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
        case .done(let today, let at, let automatic):
            let time = at.formatted(date: .omitted, time: .shortened) + (automatic ? " (automatic)" : "")
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

    private func alarmRow(_ alarm: BandAlarm) -> some View {
        HStack {
            Button {
                editingAlarm = alarm
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AlarmText.time(hour: alarm.hour, minute: alarm.minute))
                        .font(.title2.monospacedDigit())
                    Text(AlarmText.days(alarm.repeatDays) + (alarm.smartWakeupMinutes > 0 ? ", smart wake-up" : ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(alarm.isOn ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("Alarm on", isOn: Binding(get: { alarm.isOn }, set: { onToggleAlarm(alarm.id, $0) }))
                .labelsHidden()
        }
    }

    @ViewBuilder
    private var alarmStatusRow: some View {
        switch alarmStatus {
        case .idle:
            EmptyView()
        case .sending:
            busyRow("Sending alarms…")
        case .sent(let at):
            Label("Sent to the band at \(Self.clock(at))", systemImage: "alarm")
                .foregroundStyle(.green)
        case .waiting:
            Label("Saved. Sent when the band connects.", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var calendarRow: some View {
        if calendarPermissionDenied {
            Label("Calendar access is off. Turn it on in Settings > Privacy & Security > Calendars > Anew Link.",
                  systemImage: "hand.raised")
                .foregroundStyle(.orange)
        } else {
            switch calendar {
            case .idle:
                EmptyView()
            case .sent(let count, let at, let test):
                Label(test ? "Test calendar sent at \(Self.clock(at))"
                           : (count == 0 ? "No upcoming events, sent at \(Self.clock(at))"
                                         : "Sent \(count) events at \(Self.clock(at))"),
                      systemImage: test ? "testtube.2" : "calendar")
                    .foregroundStyle(test ? .orange : .green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
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
        case .done(let result) where result.automatic:
            // An automatic sync only fetched the newest data, so there's no full-day summary.
            LabeledContent("Automatic sync", value: "\(Self.clock(result.syncedAt)), \(result.samples.count) samples")
            healthRow
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

    #if DEBUG
    /// Debug only: what the band has asked for, and connection events, to design background syncing.
    private func bandRequestsSection(_ log: BandEventLog) -> some View {
        Section {
            LabeledContent("Listening", value: isListeningForRequests ? "Yes" : "No")
            if log.requestCounts.isEmpty {
                Text("No requests yet").foregroundStyle(.secondary)
            }
            ForEach(log.requestCounts, id: \.type) { entry in
                LabeledContent(entry.name, value: "\(entry.count)")
            }
            ForEach(log.events.suffix(20).reversed()) { event in
                Text("\(event.date.formatted(date: .abbreviated, time: .standard))  \(event.detail)")
                    .font(.caption.monospaced())
            }
            if !log.events.isEmpty {
                ShareLink("Share log", item: log.exportText())
                Button("Clear log", role: .destructive) { log.clear() }
            }
        } header: {
            Text("Band requests (debug)")
        } footer: {
            Text("Totals per request type since the log was cleared, then the newest 20 events. Kept across launches.")
        }
    }
    #endif

    @ViewBuilder
    private var musicRow: some View {
        if musicPermissionDenied {
            Label("Apple Music access is off. Turn it on in Settings > Privacy & Security > Media & Apple Music > Anew Link.",
                  systemImage: "hand.raised")
                .foregroundStyle(.orange)
        } else {
            switch music {
            case .idle:
                EmptyView()
            case .sent(let text, let at):
                Label(text.isEmpty
                      ? "Cleared at \(Self.clock(at)) (nothing playing)"
                      : "Sent \"\(text)\" at \(Self.clock(at))",
                      systemImage: "music.note")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
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
                    Text("\(notAllowed) not saved: that type isn't allowed in Health > Profile > Apps > Anew Link.")
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

    /// "6:40 pm" for today, otherwise "8 Nov, 6:40 pm".
    private static func dayAndTime(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month().hour().minute())
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
    /// The demo is offered when there's no band to talk to.
    private var canStartDemo: Bool {
        switch state {
        case .unsupported, .unauthorized, .poweredOff, .notFound, .failed: true
        default: false
        }
    }

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
                      timeSync: .done(at: .now, wasTest: false, timeZoneSkipped: false, automatic: true),
                      onRefresh: {})
}

#Preview("Time test sent") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      timeSync: .done(at: .now, wasTest: true, timeZoneSkipped: true, automatic: false),
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
                                     at: .now, automatic: true),
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
