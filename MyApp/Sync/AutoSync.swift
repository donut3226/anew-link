import Foundation
import Observation
import UIKit

/// Decides when the band needs fresh weather (and the time, which is sent with it).
/// Pure, so the rule can be unit-tested.
nonisolated enum WeatherSchedule {

    /// How old the last update can be before it's refreshed when the app opens.
    static let maxAge: TimeInterval = 3 * 60 * 60
    /// The band asks for weather about every 4 hours and after every reconnect. To save the
    /// band's battery, those requests are only answered when the last update is this old.
    static let minRequestGap: TimeInterval = 2 * 60 * 60

    /// Whether to answer the band's own weather request: never sent, time zone changed
    /// (travel: always worth it), or the last update is at least `minRequestGap` old.
    static func shouldAnswerRequest(lastSent: Date?, lastOffset: Int?, now: Date, currentOffset: Int) -> Bool {
        guard let lastSent, let lastOffset else { return true }
        if lastOffset != currentOffset { return true }
        return now.timeIntervalSince(lastSent) >= minRequestGap
    }

    /// - Parameters:
    ///   - lastSent: when the last successful automatic update happened (nil if never).
    ///   - lastOffset: the iPhone's time-zone offset (seconds from GMT) at that update.
    ///   - currentOffset: the offset now. A change means travel or daylight saving.
    static func isDue(lastSent: Date?, lastOffset: Int?, now: Date, currentOffset: Int,
                      calendar: Calendar = .current) -> Bool {
        guard let lastSent, let lastOffset else { return true }   // never run
        if lastOffset != currentOffset { return true }            // time zone changed
        if !calendar.isDate(lastSent, inSameDayAs: now) { return true }   // a new day
        return now.timeIntervalSince(lastSent) > maxAge           // too old
    }
}

/// Sends time and weather by itself, only if the user's switch is on: when the band asks
/// for weather (at most every 2 hours), and when the app connects or comes on screen and an
/// update is due.
@Observable
final class AutoSync {

    /// The settings key for the on/off switch (also used by `@AppStorage` in the screen).
    static let enabledKey = "autoUpdateWeatherAndTime"
    private static let lastSentKey = "autoSync.lastSent"
    private static let lastOffsetKey = "autoSync.lastOffset"

    /// When the last successful automatic update happened (saved, so it survives the app closing).
    /// Shown on screen, so you can tell "nothing was due" apart from "it never ran".
    private(set) var lastUpdate: Date?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var isRunning = false

    init() {
        lastUpdate = defaults.object(forKey: Self.lastSentKey) as? Date
    }

    /// On unless the user has switched it off.
    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Runs when the app connects or comes on screen: updates only if `WeatherSchedule` says it's due.
    func runIfDue(connection: BandConnection, weather: WeatherSync) async {
        let now = Date()
        guard WeatherSchedule.isDue(lastSent: defaults.object(forKey: Self.lastSentKey) as? Date,
                                    lastOffset: defaults.object(forKey: Self.lastOffsetKey) as? Int,
                                    now: now,
                                    currentOffset: TimeZone.current.secondsFromGMT(for: now)) else { return }
        _ = await update(connection: connection, weather: weather)
    }

    /// Runs when the band asks for weather (request type 3, about every 4 hours, also with the
    /// phone locked). The band asking is reason enough, so the schedule isn't checked.
    /// The result goes in the band log, so an overnight log shows whether each request was answered.
    func answerWeatherRequest(connection: BandConnection, weather: WeatherSync) async {
        let now = Date()
        let lastSent = defaults.object(forKey: Self.lastSentKey) as? Date
        guard WeatherSchedule.shouldAnswerRequest(lastSent: lastSent,
                                                  lastOffset: defaults.object(forKey: Self.lastOffsetKey) as? Int,
                                                  now: now,
                                                  currentOffset: TimeZone.current.secondsFromGMT(for: now)) else {
            let minutes = Int(now.timeIntervalSince(lastSent ?? now) / 60)
            connection.events.add(BandEvent(date: now, kind: .info,
                                            detail: "Weather request skipped: updated \(minutes) min ago"))
            return
        }
        let outcome = await update(connection: connection, weather: weather)
        connection.events.add(BandEvent(date: Date(), kind: .info, detail: outcome))
    }

    /// Time first, then weather. Returns a short line for the log.
    private func update(connection: BandConnection, weather: WeatherSync) async -> String {
        guard isEnabled else { return "Weather request not answered: automatic updates are off" }
        guard !isRunning, connection.state == .connected,
              !connection.isSending, !connection.activity.inProgress, !weather.isBusy else {
            return "Weather request not answered: busy"
        }
        isRunning = true
        defer { isRunning = false }

        // If the band woke the app in the background, iOS gives it only a few seconds.
        // A "background task" asks iOS for up to about 30 seconds, enough for the forecast
        // download. We must say when we're done (endBackgroundTask), or iOS closes the app.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Band update")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        let now = Date()
        let offset = TimeZone.current.secondsFromGMT(for: now)

        // If time fails (for example the band disconnected), stop and try again next time.
        guard await connection.syncTime(automatic: true) else {
            return "Weather request not answered: time sync failed"
        }

        // Never pop up the location permission automatically: only send weather if
        // the user has already allowed it (by tapping Send weather once).
        var outcome = "Answered weather request (time only, no location permission)"
        if weather.canUseLocation {
            guard await weather.sendForecast(using: connection, automatic: true) else {
                if case .failed(let reason) = weather.status {
                    return "Weather request not answered: \(reason)"
                }
                return "Weather request not answered"
            }
            outcome = "Answered weather request (time and weather)"
        }

        // Only a successful update counts, so a failure is retried next time.
        defaults.set(now, forKey: Self.lastSentKey)
        defaults.set(offset, forKey: Self.lastOffsetKey)
        lastUpdate = now
        return outcome
    }
}
