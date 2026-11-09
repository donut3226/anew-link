import SwiftUI

/// Demo mode: the whole screen with made-up data and no band, for App Review (reviewers won't
/// have a Wena 3) and for screenshots.
///
/// Every button "works" with made-up results, but nothing is sent anywhere: no Bluetooth,
/// no location, no Apple Health, no calendar. Its switches are local to the demo, so the
/// real settings are untouched.
struct DemoView: View {
    let onExit: () -> Void

    @State private var timeSync: BandConnection.TimeSyncStatus = .idle
    @State private var weather: WeatherSync.Status = .idle
    @State private var activity: BandConnection.ActivityStatus = .idle
    @State private var health: HealthSync.Status = .idle
    @State private var music: NowPlayingSync.Status = .idle
    @State private var calendar: CalendarSync.Status = .idle
    @State private var autoUpdate = true
    @State private var autoSaveActivity = true
    @State private var showSongTitle = false
    @State private var findPhone = false
    @State private var showCalendar = false
    @State private var lastActivitySave: Date?

    var body: some View {
        BandStatusContent(
            state: .connected,
            info: BandInfo(firmwareName: "2.40DEMO", serialNumber: 0),
            batteryPercent: 82,
            timeSync: timeSync,
            weather: weather,
            activity: activity,
            health: health,
            onRefresh: {},
            autoUpdate: $autoUpdate,
            lastAutoUpdate: Date().addingTimeInterval(-40 * 60),
            onSyncTime: { _ in
                timeSync = .done(at: Date(), wasTest: false, timeZoneSkipped: false, automatic: false)
            },
            onSendWeather: {
                weather = .done(today: DailyForecast(day: "demo", weatherCode: 2, minCelsius: 14, maxCelsius: 23),
                                at: Date(), automatic: false)
            },
            onSyncActivity: { activity = .done(Self.demoActivity(now: Date())) },
            onSaveToHealth: {
                health = .done(steps: 48, heartRates: 48, notAllowed: 0)
                lastActivitySave = Date()
            },
            autoSaveActivity: $autoSaveActivity,
            lastActivitySave: lastActivitySave,
            showSongTitle: $showSongTitle,
            music: showSongTitle ? .sent(text: "Demo Song / Demo Artist", at: Date()) : .idle,
            findPhoneEnabled: $findPhone,
            showCalendar: $showCalendar,
            calendar: showCalendar ? .sent(count: 3, at: Date(), test: false) : .idle,
            onExitDemo: onExit
        )
    }

    /// A made-up walk that ended a few minutes ago: 48 minutes of steps with heart rate.
    static func demoActivity(now: Date) -> BandConnection.ActivitySyncResult {
        let samples = (0..<96).map { i in
            ActivitySample(type: i.isMultiple(of: 2) ? .steps : .heartRate,
                           date: now.addingTimeInterval(TimeInterval(-(50 - i / 2) * 60)),
                           value: i.isMultiple(of: 2) ? 85 + (i % 7) * 4 : 92 + (i % 11))
        }
        return BandConnection.ActivitySyncResult(summary: ActivitySummary(samples: samples, now: now),
                                                 samples: samples, syncedAt: now, packetCount: 12,
                                                 badCRCCount: 0, receivedFinish: true)
    }
}

#Preview("Demo") {
    DemoView(onExit: {})
}
