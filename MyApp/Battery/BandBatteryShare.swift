import Foundation
import WidgetKit

/// Shares the last battery reading with the Home Screen widget through the App Group.
enum BandBatteryShare {
    /// Must match `BatteryProvider.suite` in the widget.
    static let suite = "group.com.donut32.anew-link"

    static func save(_ percent: Int, at date: Date = Date()) {
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        let changed = defaults.object(forKey: "bandBattery.percent") as? Int != percent
        defaults.set(percent, forKey: "bandBattery.percent")
        defaults.set(date, forKey: "bandBattery.readAt")
        // Only redraw the widget when the number changed (WidgetKit limits reloads).
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }
}
