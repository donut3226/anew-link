import Foundation

/// One entry to save in Apple Health, in plain Swift (no HealthKit),
/// so the conversion from band data can be unit-tested.
nonisolated struct HealthRecord: Equatable {

    enum Kind: String {
        case steps
        case heartRate
        case vo2Max
    }

    let kind: Kind
    let start: Date
    let end: Date
    let value: Double
    /// Fixed ID for this minute, so saving the same minute again replaces it instead of duplicating it.
    let syncIdentifier: String
    /// When an ID already exists in Health, a higher version replaces it.
    let syncVersion: Int
}

nonisolated enum HealthRecords {

    /// Turns band samples into Health records.
    /// - Steps: one record per minute with steps (0-step minutes are skipped), covering that minute.
    ///   The version is the step count, so a minute that was still filling up gets updated next time.
    /// - Heart rate: one record per reading, at that moment.
    /// - VO2 Max: one record per reading.
    static func make(from samples: [ActivitySample]) -> [HealthRecord] {
        samples.compactMap { sample in
            let id = "\(WenaPackets.wenaTimestamp(for: sample.date))"
            switch sample.type {
            case .steps:
                guard sample.value > 0 else { return nil }
                return HealthRecord(kind: .steps,
                                    start: sample.date,
                                    end: sample.date.addingTimeInterval(60),
                                    value: Double(sample.value),
                                    syncIdentifier: "steps-\(id)",
                                    syncVersion: sample.value)
            case .heartRate:
                return HealthRecord(kind: .heartRate,
                                    start: sample.date,
                                    end: sample.date,
                                    value: Double(sample.value),
                                    syncIdentifier: "heartRate-\(id)",
                                    syncVersion: 1)
            case .vo2:
                // One reading per day, dated midnight UTC by the band (spec 7.1).
                return HealthRecord(kind: .vo2Max,
                                    start: sample.date,
                                    end: sample.date,
                                    value: Double(sample.value),
                                    syncIdentifier: "vo2Max-\(id)",
                                    syncVersion: sample.value)
            default:
                // Calories wait until their unit is confirmed (spec 7.1); stress and body energy
                // have no Health type.
                return nil
            }
        }
    }
}
