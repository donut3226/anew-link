import Foundation
import Observation
import UIKit

/// Decides where an automatic activity sync starts. Pure, so it can be unit-tested.
nonisolated enum ActivityWindow {

    /// Re-asked each time, so minutes that were still filling up at the last sync are sent again.
    /// Health replaces them (same sync identifier) instead of adding duplicates.
    static let overlap: TimeInterval = 60 * 60
    /// The band is never asked for more than this (the same as the manual sync).
    static let maxLength: TimeInterval = 24 * 60 * 60

    /// - Parameter lastSaved: when the last successful save to Health started its sync (nil if never).
    static func start(lastSaved: Date?, now: Date) -> Date {
        let earliest = now.addingTimeInterval(-maxLength)
        guard let lastSaved else { return earliest }
        return max(lastSaved.addingTimeInterval(-overlap), earliest)
    }

    /// Automatic syncs run at most this often. Every 30 minutes was too often for the band;
    /// every 2 hours keeps Health reasonably fresh with little work for the band.
    static let minGap: TimeInterval = 2 * 60 * 60

    /// Whether an automatic sync is due: never saved, or the last save is at least `minGap` old.
    static func isDue(lastSaved: Date?, now: Date) -> Bool {
        guard let lastSaved else { return true }
        return now.timeIntervalSince(lastSaved) >= minGap
    }
}

/// Syncs activity and saves it to Apple Health about every 2 hours, also with the phone locked:
/// checked on the band's 30-minute sync tick (request type 0) and when the app opens or
/// connects, and run only when the last save is at least 2 hours old (`ActivityWindow.isDue`).
///
/// Only runs while its switch is on and after Health has been allowed once (with the
/// Save to Apple Health button), so it never shows a popup. If a save fails, the next tick
/// asks the band again from the same point, so nothing is lost.
@Observable
final class ActivityAutoSync {

    /// The settings key for the on/off switch (also used by `@AppStorage` in the screen).
    static let enabledKey = "autoSaveActivityToHealth"
    private static let lastSavedKey = "activityAutoSync.lastSaved"

    /// When the newest saved data was synced, by the automatic sync or the Save to Apple Health button.
    private(set) var lastSave: Date?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var isRunning = false

    init() {
        lastSave = defaults.object(forKey: Self.lastSavedKey) as? Date
    }

    /// On unless the user has switched it off.
    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Records a successful save, so the next automatic sync only asks for newer data.
    /// - Parameter syncedAt: when the saved data was synced from the band.
    func recordSave(syncedAt: Date) {
        if let lastSave, lastSave >= syncedAt { return }
        defaults.set(syncedAt, forKey: Self.lastSavedKey)
        lastSave = syncedAt
    }

    /// Called on the band's sync tick and when the app opens or connects. Does nothing unless
    /// a sync is due. The result goes in the band log.
    func runIfDue(connection: BandConnection, health: HealthSync) async {
        guard connection.state == .connected,
              ActivityWindow.isDue(lastSaved: lastSave, now: Date()) else { return }
        guard let outcome = await run(connection: connection, health: health) else { return }
        connection.events.add(BandEvent(date: Date(), kind: .info, detail: outcome))
    }

    /// Returns a short line for the log, or nil when there's nothing worth logging (switched off).
    private func run(connection: BandConnection, health: HealthSync) async -> String? {
        guard isEnabled else { return nil }
        guard health.canSaveWithoutAsking else {
            return "Activity not synced: tap Save to Apple Health once to allow it"
        }
        guard connection.info?.supportsActivitySync == true else {
            return "Activity not synced: firmware not read yet, or older than 2.40"
        }
        guard !isRunning, connection.state == .connected,
              !connection.isSending, !connection.activity.inProgress, !health.isBusy else {
            return "Activity not synced: busy"
        }
        isRunning = true
        defer { isRunning = false }

        // Ask iOS for up to about 30 seconds in the background (see AutoSync).
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Activity sync")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        let since = ActivityWindow.start(lastSaved: lastSave, now: Date())
        let status = await connection.syncActivityAndWait(since: since)
        guard case .done(let result) = status else {
            if case .failed(let reason) = status { return "Activity sync failed: \(reason)" }
            return "Activity sync failed"
        }

        guard await health.save(result.samples, firmware: connection.info?.firmwareName, askPermission: false) else {
            if case .failed(let reason) = health.status { return "Activity not saved: \(reason)" }
            return "Activity not saved"
        }
        recordSave(syncedAt: result.syncedAt)
        return "Saved activity to Health (\(result.samples.count) samples)"
    }
}
