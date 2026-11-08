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
            onRefresh: { connection.refresh() }
        )
        .onAppear { connection.start() }
        .onDisappear { connection.stop() }
    }
}

struct BandStatusContent: View {
    let state: BandConnection.State
    let info: BandInfo?
    let batteryPercent: Int?
    let onRefresh: () -> Void

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
