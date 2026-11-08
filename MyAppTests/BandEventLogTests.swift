import Foundation
import Testing
@testable import MyApp

/// The log is a main-thread class, so these tests run on the main actor too.
@MainActor
struct BandEventLogTests {

    /// A fresh temporary file for each test, so tests never touch the app's real log.
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BandEventLogTests-\(UUID().uuidString)")
            .appendingPathComponent("log.json")
    }

    @Test func savesAndLoadsBack() throws {
        let file = tempFile()
        let log = BandEventLog(fileURL: file)
        log.add(BandEvent(date: Date(timeIntervalSince1970: 1_000), kind: .connected, detail: "Connected"))
        log.addRequest(try #require(BandRequest(Data([3]))), raw: Data([3]), at: Date(timeIntervalSince1970: 2_000))

        let reloaded = BandEventLog(fileURL: file)
        #expect(reloaded.events == log.events)
        #expect(reloaded.events.last?.detail == "Get weather")
        #expect(reloaded.events.last?.hex == "03")
    }

    @Test func keepsOnlyTheNewestEntries() {
        let log = BandEventLog(fileURL: tempFile())
        for index in 0..<(BandEventLog.maxEntries + 5) {
            log.add(BandEvent(date: Date(timeIntervalSince1970: TimeInterval(index)), kind: .info, detail: "\(index)"))
        }
        #expect(log.events.count == BandEventLog.maxEntries)
        #expect(log.events.first?.detail == "5")
        #expect(log.events.last?.detail == "\(BandEventLog.maxEntries + 4)")
    }

    @Test func countsRequestsPerType() throws {
        let log = BandEventLog(fileURL: tempFile())
        for type: UInt8 in [0, 0, 0, 3, 4] {
            log.addRequest(try #require(BandRequest(Data([type]))), raw: Data([type]))
        }
        log.add(BandEvent(date: Date(), kind: .connected, detail: "Connected"))   // not a request

        let counts = log.requestCounts
        #expect(counts.map(\.type) == [0, 3, 4])
        #expect(counts.map(\.count) == [3, 1, 1])
        #expect(counts.first?.name == "Sync tick")
    }

    @Test func clearEmptiesTheLog() {
        let file = tempFile()
        let log = BandEventLog(fileURL: file)
        log.add(BandEvent(date: Date(), kind: .info, detail: "x"))
        log.clear()
        #expect(log.events.isEmpty)
        #expect(BandEventLog(fileURL: file).events.isEmpty)
    }
}
