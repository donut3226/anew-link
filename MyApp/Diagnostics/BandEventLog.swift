import Foundation
import Observation

/// One line in the band event log.
nonisolated struct BandEvent: Codable, Equatable, Identifiable {

    enum Kind: String, Codable {
        case request        // the band asked for something on 4002
        case connected
        case disconnected
        case reconnecting
        case info           // anything else worth noting, for example "listening"
    }

    var id = UUID()
    let date: Date
    let kind: Kind
    /// Only for requests: the request type byte.
    var requestType: UInt8?
    let detail: String
    /// The raw bytes as hex (requests only). A few bytes, never personal data.
    var hex: String = ""
}

/// A record of what the band sends and how the connection behaves, saved across launches.
/// Used to learn how often the band asks for things, so background syncing can be designed.
@Observable
final class BandEventLog {

    static let maxEntries = 1_000

    private(set) var events: [BandEvent] = []

    @ObservationIgnored private let fileURL: URL

    /// - Parameter fileURL: where to save. Tests pass a temporary file.
    init(fileURL: URL = BandEventLog.defaultFileURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([BandEvent].self, from: data) {
            events = saved
        }
    }

    /// Application Support is the app's private folder for files it manages itself.
    static var defaultFileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("band-events.json")
    }

    func add(_ event: BandEvent) {
        events.append(event)
        if events.count > Self.maxEntries {
            events.removeFirst(events.count - Self.maxEntries)   // keep the newest
        }
        save()
    }

    func addRequest(_ request: BandRequest, raw: Data, at date: Date = Date()) {
        add(BandEvent(date: date, kind: .request, requestType: request.type,
                      detail: request.name + (request.notificationID.map { " (id \($0))" } ?? ""),
                      hex: raw.map { String(format: "%02X", $0) }.joined(separator: " ")))
    }

    func clear() {
        events = []
        save()
    }

    /// How many of each request type, most common first.
    var requestCounts: [(type: UInt8, name: String, count: Int)] {
        let types = events.compactMap { $0.kind == .request ? $0.requestType : nil }
        return Dictionary(grouping: types, by: { $0 })
            .map { (type: $0.key, name: BandRequest.name(forType: $0.key), count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.type < $1.type }
    }

    /// The whole log as text, one event per line, for sharing.
    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return events.map { event in
            [formatter.string(from: event.date), event.kind.rawValue, event.detail, event.hex]
                .filter { !$0.isEmpty }
                .joined(separator: "  ")
        }
        .joined(separator: "\n")
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(events).write(to: fileURL, options: .atomic)
        } catch {
            // Not worth interrupting anything for: the log is a diagnostic aid.
        }
    }
}
