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
    /// Latest body energy (0-100) and stress (0-100) readings, if the band sent any (spec 7.1).
    var latestBodyEnergy: Int?
    var latestStress: Int?
    /// The newest VO2 Max reading (ml/kg/min).
    var vo2Max: Int?
    /// Calories since midnight in kcal, assuming the band counts 1/1000 kcal (UNVERIFIED, spec 7.1).
    var caloriesToday: Int?
    /// Which part of today the calorie minutes cover (to check the total against the band's screen).
    var caloriesFrom: Date?
    var caloriesTo: Date?
    var calorieMinutes = 0

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

        latestBodyEnergy = Self.latest(.bodyEnergy, in: samples)
        latestStress = Self.latest(.stress, in: samples)
        vo2Max = Self.latest(.vo2, in: samples)
        let calories = samples.filter { $0.type == .calories && $0.date >= midnight }
        calorieMinutes = calories.count
        caloriesFrom = calories.map(\.date).min()
        caloriesTo = calories.map(\.date).max()
        if !calories.isEmpty {
            caloriesToday = Int((Double(calories.reduce(0) { $0 + $1.value }) / 1000).rounded())
        }

        newestSampleAt = samples.filter { $0.type != .vo2 }.map(\.date).max()
        if let newest = newestSampleAt {
            newestSampleMinutesAgo = Int(now.timeIntervalSince(newest) / 60)
        }
    }

    private static func latest(_ type: ActivityDataType, in samples: [ActivitySample]) -> Int? {
        samples.filter { $0.type == type }.max { $0.date < $1.date }?.value
    }
}
