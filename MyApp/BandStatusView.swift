import SwiftUI

/// The first screen: finds the band and shows its firmware, battery and serial.
///
/// This view owns the Bluetooth object and starts or stops it.
/// The drawing itself happens in `BandStatusContent` below, which only takes plain values,
/// so previews can show every state with fake data and no Bluetooth.
struct BandStatusView: View {
    // @State keeps the same BandConnection alive while this screen is on display.
    @State private var connection = BandConnection()

    var body: some View {
        BandStatusContent(
            state: connection.state,
            info: connection.info,
            batteryPercent: connection.batteryPercent,
            timeSync: connection.timeSync,
            onRefresh: { connection.refresh() },
            onSyncTime: { offset in connection.syncTime(offsetSeconds: offset) }
        )
        .onAppear { connection.start() }
        .onDisappear { connection.stop() }
    }
}

struct BandStatusContent: View {
    let state: BandConnection.State
    let info: BandInfo?
    let batteryPercent: Int?
    var timeSync: BandConnection.TimeSyncStatus = .idle
    let onRefresh: () -> Void
    /// Called with how many seconds to add to the time sent: 0 normally, 300 for the debug test.
    var onSyncTime: (TimeInterval) -> Void = { _ in }

    // Hidden by default so the serial doesn't end up in screenshots.
    @State private var showSerial = false

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    statusRow
                }

                if state == .connected {
                    Section("Band") {
                        LabeledContent("Firmware", value: info?.firmwareName ?? "Reading…")
                        LabeledContent("Battery", value: batteryPercent.map { "\($0)%" } ?? "Reading…")
                        serialRow
                    }

                    Section("Time") {
                        Button("Sync time") { onSyncTime(0) }
                            .disabled(timeSync == .sending)
                        timeSyncRow
                    }

                    // #if DEBUG: this section only exists in builds run from Xcode,
                    // never in App Store builds.
                    #if DEBUG
                    Section {
                        Button("Test: set band 5 min fast") { onSyncTime(5 * 60) }
                            .disabled(timeSync == .sending)
                    } header: {
                        Text("Debug only")
                    } footer: {
                        Text("Proves the time packet works. Tap Sync time afterwards to put the band's clock right.")
                    }
                    #endif
                }

                if let buttonTitle {
                    Section {
                        Button(buttonTitle, action: onRefresh)
                    }
                }
            }
            .navigationTitle("Buckle Link")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch state {
        case .starting:
            busyRow("Starting Bluetooth…")
        case .unsupported:
            Label("Bluetooth isn't available on this device. Run the app on your iPhone.",
                  systemImage: "antenna.radiowaves.left.and.right.slash")
        case .unauthorized:
            Label("Bluetooth permission is off. Turn it on in Settings > Privacy & Security > Bluetooth.",
                  systemImage: "hand.raised")
        case .poweredOff:
            Label("Bluetooth is turned off.", systemImage: "antenna.radiowaves.left.and.right.slash")
        case .searching:
            busyRow("Looking for your band…")
        case .notFound:
            Label("Band not found. Keep it nearby with its screen on, and check it shows as Connected in Settings > Bluetooth.",
                  systemImage: "questionmark.circle")
        case .connecting:
            busyRow("Connecting…")
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var serialRow: some View {
        if let info {
            if showSerial {
                LabeledContent("Serial", value: String(info.serialNumber))
                    .privacySensitive()
                    .onTapGesture { showSerial = false }
            } else {
                Button("Show serial") { showSerial = true }
            }
        }
    }

    @ViewBuilder
    private var timeSyncRow: some View {
        switch timeSync {
        case .idle:
            EmptyView()
        case .sending:
            busyRow("Syncing time…")
        case .done(let at, let wasTest, let timeZoneSkipped):
            VStack(alignment: .leading, spacing: 4) {
                Label(wasTest
                      ? "Test sent at \(at.formatted(date: .omitted, time: .shortened)): band should be 5 min fast"
                      : "Time synced at \(at.formatted(date: .omitted, time: .shortened))",
                      systemImage: wasTest ? "testtube.2" : "checkmark.circle.fill")
                    .foregroundStyle(wasTest ? .orange : .green)
                if timeZoneSkipped {
                    Text("Time zone not sent: the band's handling of your zone isn't verified yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private func busyRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
        }
    }

    /// Which button to show, if any, for the current state.
    private var buttonTitle: String? {
        switch state {
        case .connected: "Refresh"
        case .notFound, .failed: "Try again"
        default: nil
        }
    }
}

// Previews use obviously fake values. Never put the real band's serial here.

#Preview("Connected") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      onRefresh: {})
}

#Preview("Time synced") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      timeSync: .done(at: .now, wasTest: false, timeZoneSkipped: false),
                      onRefresh: {})
}

#Preview("Time test sent") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      timeSync: .done(at: .now, wasTest: true, timeZoneSkipped: true),
                      onRefresh: {})
}

#Preview("Time sync failed") {
    BandStatusContent(state: .connected,
                      info: BandInfo(firmwareName: "PREVIEW", serialNumber: 0),
                      batteryPercent: 80,
                      timeSync: .failed("The band didn't accept the time."),
                      onRefresh: {})
}

#Preview("Searching") {
    BandStatusContent(state: .searching, info: nil, batteryPercent: nil, onRefresh: {})
}

#Preview("Not found") {
    BandStatusContent(state: .notFound, info: nil, batteryPercent: nil, onRefresh: {})
}

#Preview("Failed") {
    BandStatusContent(state: .failed("Lost the connection to the band."),
                      info: nil, batteryPercent: nil, onRefresh: {})
}
