import SwiftUI
import WidgetKit

/// The band's battery on the Home Screen or Lock Screen. The app saves each battery reading in
/// the shared App Group (`BandBatteryShare` in the app); this widget only shows the last one.
@main
struct AnewLinkWidgets: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BandBattery", provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Band battery")
        .description("Your band's battery, from the last time Anew Link read it.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let percent: Int?
    let readAt: Date?
}

struct BatteryProvider: TimelineProvider {
    /// Must match `BandBatteryShare` in the app.
    static let suite = "group.com.donut32.anew-link"

    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), percent: 80, readAt: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        // The app asks WidgetKit to reload after each reading; this is only a fallback.
        completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(60 * 60))))
    }

    private func current() -> BatteryEntry {
        let defaults = UserDefaults(suiteName: Self.suite)
        let percent = defaults?.object(forKey: "bandBattery.percent") as? Int
        let readAt = defaults?.object(forKey: "bandBattery.readAt") as? Date
        return BatteryEntry(date: Date(), percent: percent, readAt: readAt)
    }
}

struct BatteryWidgetView: View {
    let entry: BatteryEntry
    @Environment(\.widgetFamily) private var family

    private var fraction: Double { Double(entry.percent ?? 0) / 100 }
    private var percentText: String { entry.percent.map { "\($0)%" } ?? "--" }
    private var symbol: String {
        guard let p = entry.percent else { return "battery.0percent" }
        switch p {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: fraction) {
                Image(systemName: "applewatch.side.right")
            } currentValueLabel: {
                Text(entry.percent.map(String.init) ?? "--")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryInline:
            Label("Band \(percentText)", systemImage: symbol)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Band", systemImage: symbol)
                Text(percentText).font(.title2.bold())
                if let readAt = entry.readAt {
                    Text(readAt, style: .relative).font(.caption2)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label("Band", systemImage: "applewatch.side.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle((entry.percent ?? 100) <= 20 ? .red : .green)
                Text(percentText)
                    .font(.largeTitle.bold())
                if let readAt = entry.readAt {
                    Text(readAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Open Anew Link").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview(as: .systemSmall) {
    BatteryWidget()
} timeline: {
    BatteryEntry(date: .now, percent: 82, readAt: .now.addingTimeInterval(-600))
    BatteryEntry(date: .now, percent: 15, readAt: .now)
}
