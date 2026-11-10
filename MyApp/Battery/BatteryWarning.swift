import Foundation
import Observation
import UserNotifications

/// When to warn about the band's battery. Pure, so it can be tested.
nonisolated enum BatteryWarningRule {
    /// Warn at or below this percentage.
    static let low = 20
    /// Warn again only after the battery has been charged above this.
    static let rearm = 30

    /// - Returns: whether to warn now, and the new "already warned" state.
    static func next(percent: Int, alreadyWarned: Bool) -> (warn: Bool, warned: Bool) {
        if percent > rearm { return (false, false) }
        if percent <= low, !alreadyWarned { return (true, true) }
        return (false, alreadyWarned)
    }
}

/// Shows a notification on the iPhone once when the band's battery runs low.
/// The battery is read each time the band connects (often, in the background too).
/// Off until the user switches it on, which is also when notification permission is asked.
@Observable
final class BatteryWarning {

    static let enabledKey = "batteryWarningEnabled"
    private static let warnedKey = "batteryWarning.warned"

    private(set) var permissionDenied = false

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    func enabledChanged() async {
        guard isEnabled else { return }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        permissionDenied = !granted
    }

    /// Called with every battery reading from the band.
    func batteryRead(_ percent: Int) {
        let defaults = UserDefaults.standard
        let step = BatteryWarningRule.next(percent: percent, alreadyWarned: defaults.bool(forKey: Self.warnedKey))
        defaults.set(step.warned, forKey: Self.warnedKey)
        guard step.warn, isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Band battery low"
        content.body = "Your band is at \(percent)%. Charge it soon."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "batteryLow", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
