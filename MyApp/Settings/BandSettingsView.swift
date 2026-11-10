import SwiftUI

/// The band's own settings: vibration, display, home icons, button, goals and quiet times.
///
/// Takes plain values so previews and the demo need no Bluetooth. Every change calls `onChange`
/// with the new values, which sends only the setting that changed (like Sony's app).
struct BandSettingsView: View {
    let settings: BandSettings
    var status: BandSettingsStore.Status = .idle
    var isBusy = false
    let onChange: (BandSettings) -> Void
    var onSendAll: () -> Void = {}
    var onTestVibration: () -> Void = {}

    var body: some View {
        Form {
            Section {
                statusRow
            } footer: {
                Text("Each change is sent to the band straight away. The band can't report its settings back, so this screen shows what Anew Link last sent.")
            }

            Section {
                Picker("Strength", selection: binding(\.vibration)) {
                    ForEach(BandSettings.Strength.ordered) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("Feel it on the band", systemImage: "waveform", action: onTestVibration)
                    .disabled(isBusy)
                Toggle("Stop vibrating at rest", isOn: binding(\.stopVibratingAtRest))
            } header: {
                Text("Vibration")
            } footer: {
                Text("Feel it sends one test notification, so the band buzzes once at this strength.")
            }

            Section {
                Picker("Wrist", selection: binding(\.leftWrist)) {
                    Text("Left").tag(true)
                    Text("Right").tag(false)
                }
                Toggle("Large font", isOn: binding(\.largeFont))
                Toggle("Wake screen when lifting wrist", isOn: binding(\.raiseToWake))
                Picker("Language", selection: binding(\.japanese)) {
                    Text("English").tag(false)
                    Text("Japanese").tag(true)
                }
            } header: {
                Text("Display")
            }

            Section {
                iconPicker("Left", \.homeLeft, others: [settings.homeCentre, settings.homeRight])
                iconPicker("Centre", \.homeCentre, others: [settings.homeLeft, settings.homeRight])
                iconPicker("Right", \.homeRight, others: [settings.homeLeft, settings.homeCentre])
                Picker("Design", selection: binding(\.richHomeDesign)) {
                    Text("Normal").tag(false)
                    Text("Rich").tag(true)
                }
            } header: {
                Text("Home screen")
            }

            Section {
                NavigationLink("Status pages") {
                    OrderEditor(title: "Status pages", items: settings.statusOrder, label: \.label,
                                footer: "Swipe up on the band's clock to see these pages, in this order.") { order in
                        var new = settings
                        new.statusOrder = order
                        onChange(new)
                    }
                }
                NavigationLink("Tool menu") {
                    OrderEditor(title: "Tool menu", items: settings.menuOrder, label: \.label,
                                footer: "The band's tool menu, in this order. Items whose services have ended stay on the list, because the band expects every item.") { order in
                        var new = settings
                        new.menuOrder = order
                        onChange(new)
                    }
                }
            } header: {
                Text("Order on the band")
            } footer: {
                Text("Drag to reorder. Each change is sent straight away.")
            }

            Section {
                actionPicker("Long press", \.longPress)
                actionPicker("Double press", \.doublePress)
            } header: {
                Text("Band button")
            }

            Section {
                Stepper("Step goal: \(settings.stepGoal.formatted())",
                        value: binding(\.stepGoal), in: 1000...50000, step: 500)
                Toggle("Notify when goal reached", isOn: binding(\.goalNotification))
                Picker("Day starts at", selection: binding(\.dayStartHour)) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(AlarmText.time(hour: hour, minute: 0)).tag(hour)
                    }
                }
            } header: {
                Text("Activity")
            }

            Section {
                if let body = settings.body {
                    bodyRows(body)
                } else {
                    Button("Add body details", systemImage: "figure") {
                        var new = settings
                        new.body = BodyDetails()
                        onChange(new)
                    }
                }
            } header: {
                Text("Body details")
            } footer: {
                Text("Used by the band to estimate calories, body energy and VO2 Max. Kept on this phone and sent only to the band.")
            }

            Section {
                Toggle("Do not disturb", isOn: binding(\.doNotDisturbOn))
                if settings.doNotDisturbOn {
                    timePicker("From", \.doNotDisturbStart)
                    timePicker("Until", \.doNotDisturbEnd)
                }
            } header: {
                Text("Quiet times")
            } footer: {
                Text("Do not disturb stops the screen waking and silences calls and notifications on the band.")
            }

            Section {
                Toggle("Turn off automatically", isOn: binding(\.autoPowerOffOn))
                if settings.autoPowerOffOn {
                    timePicker("Off at", \.autoPowerOffStart)
                    timePicker("On at", \.autoPowerOffEnd)
                }
            } footer: {
                Text("The band switches itself off and back on every day at these times, to save battery.")
            }

            Section {
                Toggle("Vibrate when the phone is out of range", isOn: binding(\.disconnectAlertOn))
                if settings.disconnectAlertOn {
                    Picker("After", selection: binding(\.disconnectAlertSeconds)) {
                        ForEach(BandSettings.disconnectDelayChoices, id: \.self) { seconds in
                            Text(Self.delayText(seconds)).tag(seconds)
                        }
                    }
                }
            } header: {
                Text("Disconnection alert")
            }

            Section {
                Button("Send all settings to the band", action: onSendAll)
                    .disabled(isBusy)
            } footer: {
                Text("Use this after the band was reset, or set up with another app, so it matches this screen.")
            }
        }
        .navigationTitle("Band settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Rows

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .idle:
            Label("No changes sent yet", systemImage: "slider.horizontal.3")
                .foregroundStyle(.secondary)
        case .sending:
            HStack {
                ProgressView()
                Text("Sending…")
            }
        case .sent(let at):
            Label("Sent to the band at \(at.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .buzzed(let at):
            Label("Test buzz sent at \(at.formatted(date: .omitted, time: .shortened))", systemImage: "waveform")
                .foregroundStyle(.green)
        case .waiting:
            Label("Saved. Sent when the band connects.", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    /// Each slot can't show an icon another slot already uses (as on Sony's app).
    private func iconPicker(_ title: String, _ key: WritableKeyPath<BandSettings, HomeIcon>, others: [HomeIcon]) -> some View {
        Picker(title, selection: binding(key)) {
            ForEach(HomeIcon.allCases.filter { !others.contains($0) }) { Text($0.label).tag($0) }
        }
    }

    private func actionPicker(_ title: String, _ key: WritableKeyPath<BandSettings, ButtonAction>) -> some View {
        Picker(title, selection: binding(key)) {
            ForEach(ButtonAction.allCases) { Text($0.label).tag($0) }
        }
    }

    @ViewBuilder
    private func bodyRows(_ body: BodyDetails) -> some View {
        DatePicker("Birth date", selection: Binding(
            get: {
                Calendar.current.date(from: DateComponents(year: body.birthYear, month: body.birthMonth, day: body.birthDay)) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
                changeBody { $0.birthYear = parts.year ?? body.birthYear; $0.birthMonth = parts.month ?? 1; $0.birthDay = parts.day ?? 1 }
            }
        ), in: ...Date(), displayedComponents: .date)
        Picker("Sex", selection: Binding(get: { body.sex }, set: { sex in changeBody { $0.sex = sex } })) {
            ForEach(BodyDetails.Sex.allCases) { Text($0.label).tag($0) }
        }
        Stepper("Height: \(Int(body.heightCm)) cm",
                value: Binding(get: { body.heightCm }, set: { v in changeBody { $0.heightCm = v } }), in: 100...230, step: 1)
        Stepper("Weight: \(body.weightKg.formatted(.number.precision(.fractionLength(1)))) kg",
                value: Binding(get: { body.weightKg }, set: { v in changeBody { $0.weightKg = v } }), in: 30...200, step: 0.5)
    }

    private func changeBody(_ change: (inout BodyDetails) -> Void) {
        guard var body = settings.body else { return }
        change(&body)
        var new = settings
        new.body = body
        onChange(new)
    }

    private func timePicker(_ title: String, _ key: WritableKeyPath<BandSettings, BandClockTime>) -> some View {
        DatePicker(title, selection: Binding(
            get: {
                let time = settings[keyPath: key]
                return Calendar.current.date(from: DateComponents(hour: time.hour, minute: time.minute)) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                var new = settings
                new[keyPath: key] = BandClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
                onChange(new)
            }
        ), displayedComponents: .hourAndMinute)
    }

    /// A Binding that reads from `settings` and sends a changed copy through `onChange`.
    private func binding<T>(_ key: WritableKeyPath<BandSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: key] },
            set: { value in
                var new = settings
                new[keyPath: key] = value
                onChange(new)
            }
        )
    }

    static func delayText(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) seconds" : (seconds == 60 ? "1 minute" : "\(seconds / 60) minutes")
    }
}

/// A drag-to-reorder list. Each move calls `onChange` with the new order.
struct OrderEditor<Item: Identifiable & Hashable>: View {
    let title: String
    let items: [Item]
    let label: KeyPath<Item, String>
    var footer = ""
    let onChange: ([Item]) -> Void

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    Text(item[keyPath: label])
                }
                .onMove { from, to in
                    var moved = items
                    moved.move(fromOffsets: from, toOffset: to)
                    onChange(moved)
                }
            } footer: {
                Text(footer)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Band settings") {
    @Previewable @State var settings = BandSettings()
    NavigationStack {
        BandSettingsView(settings: settings, status: .sent(at: Date()), onChange: { settings = $0 })
    }
}
