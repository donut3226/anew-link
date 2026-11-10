import Foundation
import Testing
@testable import MyApp

/// Checks the band-data-to-Health conversion. All values are made up.
struct HealthRecordsTests {

    private let start = WenaPackets.date(fromWenaTimestamp: 216_259_200)   // 2026-11-08 00:00 UTC

    @Test func stepsBecomeOneRecordPerMinute() {
        let samples = [
            ActivitySample(type: .steps, date: start, value: 12),
            ActivitySample(type: .steps, date: start.addingTimeInterval(60), value: 30),
        ]
        #expect(HealthRecords.make(from: samples) == [
            HealthRecord(kind: .steps, start: start, end: start.addingTimeInterval(60),
                         value: 12, syncIdentifier: "steps-216259200", syncVersion: 12),
            HealthRecord(kind: .steps, start: start.addingTimeInterval(60), end: start.addingTimeInterval(120),
                         value: 30, syncIdentifier: "steps-216259260", syncVersion: 30),
        ])
    }

    @Test func zeroStepMinutesAreSkipped() {
        let samples = [
            ActivitySample(type: .steps, date: start, value: 0),
            ActivitySample(type: .steps, date: start.addingTimeInterval(60), value: 5),
        ]
        #expect(HealthRecords.make(from: samples).map(\.syncIdentifier) == ["steps-216259260"])
    }

    @Test func heartRateIsAMomentReading() {
        let samples = [ActivitySample(type: .heartRate, date: start, value: 64)]
        #expect(HealthRecords.make(from: samples) == [
            HealthRecord(kind: .heartRate, start: start, end: start,
                         value: 64, syncIdentifier: "heartRate-216259200", syncVersion: 1),
        ])
    }

    @Test func sameInputGivesSameIdentifiers() {
        let samples = [
            ActivitySample(type: .steps, date: start, value: 7),
            ActivitySample(type: .heartRate, date: start, value: 70),
        ]
        #expect(HealthRecords.make(from: samples).map(\.syncIdentifier)
                == HealthRecords.make(from: samples).map(\.syncIdentifier))
        // Steps and heart rate for the same minute must not share an ID.
        #expect(Set(HealthRecords.make(from: samples).map(\.syncIdentifier)).count == 2)
    }

    @Test func otherTypesAreIgnored() {
        let samples = [ActivitySample(type: .stress, date: start, value: 40),
                       ActivitySample(type: .calories, date: start, value: 734),
                       ActivitySample(type: .bodyEnergy, date: start, value: 60)]
        #expect(HealthRecords.make(from: samples).isEmpty)
    }

    @Test func vo2MaxBecomesOneRecord() {
        let records = HealthRecords.make(from: [ActivitySample(type: .vo2, date: start, value: 43)])
        #expect(records.count == 1)
        #expect(records[0].kind == .vo2Max)
        #expect(records[0].value == 43)
        #expect(records[0].syncIdentifier.hasPrefix("vo2Max-"))
    }
}
