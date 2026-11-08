import Foundation

/// The numbers shown on screen after an activity sync, worked out from the samples.
nonisolated struct ActivitySummary: Equatable {
    var stepsToday = 0
    var stepsLast24Hours = 0
    var latestHeartRate: Int?
    var latestHeartRateAt: Date?
    var heartRateMin: Int?
    var heartRateMax: Int?
    /// The newest sample of any type. Because the band stamps samples with its own clock,
    /// this being a few minutes before the sync proves the band's clock is right.
    var newestSampleAt: Date?
    var newestSampleMinutesAgo: Int?
    var stepMinuteCount = 0
    var heartRateCount = 0

    /// - Parameters:
    ///   - now: when the sync happened.
    ///   - calendar: decides when "today" started (local midnight).
    init(samples: [ActivitySample], now: Date, calendar: Calendar = .current) {
        let midnight = calendar.startOfDay(for: now)
        let dayAgo = now.addingTimeInterval(-24 * 60 * 60)

        let steps = samples.filter { $0.type == .steps }
        stepMinuteCount = steps.count
        stepsToday = steps.filter { $0.date >= midnight }.reduce(0) { $0 + $1.value }
        stepsLast24Hours = steps.filter { $0.date >= dayAgo }.reduce(0) { $0 + $1.value }

        let heartRates = samples.filter { $0.type == .heartRate }
        heartRateCount = heartRates.count
        if let latest = heartRates.max(by: { $0.date < $1.date }) {
            latestHeartRate = latest.value
            latestHeartRateAt = latest.date
        }
        heartRateMin = heartRates.map(\.value).min()
        heartRateMax = heartRates.map(\.value).max()

        newestSampleAt = samples.map(\.date).max()
        if let newest = newestSampleAt {
            newestSampleMinutesAgo = Int(now.timeIntervalSince(newest) / 60)
        }
    }
}
