import SwiftUI

/// Which iPhone apps reach the band, and how each one lights and vibrates (spec 15.3).
///
/// Takes plain values so previews and the demo need no Bluetooth. Every change calls `onChange`
/// with the whole new list, which is sent to the band straight away.
struct NotificationAppsView: View {
    let apps: [NotifyApp]
    var status: NotificationAppsStore.Status = .idle
    var isBusy = false
    /// False until the band's list characteristic has been found (spec 15.1).
    var listFound = true
    /// The list characteristic's short id once found (for example "1530"), shown so it can be noted in the spec.
    var listID: String?
    var neverSent = false
    let onChange: ([NotifyApp]) -> Void
    var onTry: (NotifyApp) -> Void = { _ in }

    @State private var editing: NotifyApp?
    @State private var adding = false

    private var appEntries: [NotifyApp] { apps.filter { $0.kind == .app } }
    private var call: NotifyApp? { apps.first { $0.kind == .call } }

    var body: some View {
        Form {
            Section {
                statusRow
                if let listID {
                    LabeledContent("Band's list found", value: listID)
                }
                if !listFound {
                    Label("The band's notification list hasn't been found yet. Connect the band and tap Refresh.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text(neverSent
                     ? "Your band keeps the list it was last given. Changing anything here replaces it with this list."
                     : "Each change is sent to the band straight away and replaces the band's list.")
            }

            Section {
                ForEach(appEntries) { app in
                    row(app)
                }
                .onDelete { offsets in
                    let ids = offsets.map { appEntries[$0].id }
                    onChange(apps.filter { !ids.contains($0.id) })
                }
                .onMove { from, to in
                    var moved = appEntries
                    moved.move(fromOffsets: from, toOffset: to)
                    onChange(moved + apps.filter { $0.kind == .call })
                }
                if appEntries.count < WenaNotificationList.maxApps {
                    Button("Add an app", systemImage: "plus") { adding = true }
                }
            } header: {
                Text("Apps")
            } footer: {
                Text("The band shows notifications only from apps on this list. The name must match the app's name on your Home Screen.")
            }

            if let call {
                Section {
                    row(call)
                } header: {
                    Text("Phone")
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(item: $editing) { app in
            NotifyAppEditor(app: app, isBusy: isBusy,
                            onSave: { saved in
                                onChange(apps.map { $0.id == saved.id ? saved : $0 })
                                editing = nil
                            },
                            onTry: onTry,
                            onCancel: { editing = nil })
        }
        .sheet(isPresented: $adding) {
            AddNotifyAppSheet(existing: Set(appEntries.map { $0.name.lowercased() }),
                              onAdd: { name in
                                  onChange(appEntries + [NotifyApp(name: name)] + apps.filter { $0.kind == .call })
                                  adding = false
                              },
                              onCancel: { adding = false })
        }
    }

    private func row(_ app: NotifyApp) -> some View {
        Button {
            editing = app
        } label: {
            HStack {
                Circle()
                    .fill(Self.swatch(app.colour))
                    .overlay(Circle().stroke(.secondary.opacity(0.4)))
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading) {
                    Text(app.displayName)
                        .foregroundStyle(.primary)
                    Text(app.isOn ? "\(app.pattern.label), \(app.count.label.lowercased())" : "Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .idle:
            Label("No changes sent yet", systemImage: "bell.badge")
                .foregroundStyle(.secondary)
        case .sending:
            HStack {
                ProgressView()
                Text("Sending…")
            }
        case .sent(let at):
            Label("Sent to the band at \(at.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .waiting:
            Label("Saved. Sent when the band connects.", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    static func swatch(_ colour: NotifyColour) -> Color {
        switch colour {
        case .red: .red
        case .yellow: .yellow
        case .green: .green
        case .cyan: .cyan
        case .blue: .blue
        case .purple: .purple
        case .white: .white
        }
    }
}

/// Edit one app's notification settings (shown as a sheet). Sent on Save, like Sony's app.
struct NotifyAppEditor: View {
    var isBusy = false
    let onSave: (NotifyApp) -> Void
    var onTry: (NotifyApp) -> Void = { _ in }
    let onCancel: () -> Void

    @State private var app: NotifyApp

    init(app: NotifyApp, isBusy: Bool = false, onSave: @escaping (NotifyApp) -> Void,
         onTry: @escaping (NotifyApp) -> Void = { _ in }, onCancel: @escaping () -> Void) {
        self.isBusy = isBusy
        self.onSave = onSave
        self.onTry = onTry
        self.onCancel = onCancel
        _app = State(initialValue: app)
    }

    var body: some View {
        NavigationStack {
            Form {
                if app.kind == .app {
                    Section {
                        TextField("App name", text: $app.name)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Exactly as it appears under the app's icon on your Home Screen.")
                    }
                }
                Section {
                    Toggle("Show on the band", isOn: $app.isOn)
                    Picker("Light", selection: $app.colour) {
                        ForEach(NotifyColour.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Vibration", selection: $app.pattern) {
                        ForEach(app.kind == .call ? NotifyPattern.forCalls : NotifyPattern.forApps) { Text($0.label).tag($0) }
                    }
                    Picker("Times", selection: $app.count) {
                        ForEach(NotifyCount.allCases) { Text($0.label).tag($0) }
                    }
                    Button("Try it on the band", systemImage: "waveform") { onTry(app) }
                        .disabled(isBusy)
                } footer: {
                    Text("Try it sends one test notification with this light and vibration. Repeat is tried as twice.")
                }
            }
            .navigationTitle(app.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(app) }
                        .disabled(app.kind == .app && WenaNotificationList.nameBytes(app.name).isEmpty)
                }
            }
        }
    }
}

/// Pick a common app or type a name.
struct AddNotifyAppSheet: View {
    /// Names already on the list, lowercased.
    let existing: Set<String>
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    @State private var custom = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("App name", text: $custom)
                        .autocorrectionDisabled()
                        .onSubmit(addCustom)
                    Button("Add \"\(custom.trimmingCharacters(in: .whitespaces))\"", action: addCustom)
                        .disabled(!canAdd(custom))
                } header: {
                    Text("Any app")
                } footer: {
                    Text("Type the name exactly as it appears under the app's icon on your Home Screen.")
                }
                Section {
                    ForEach(WenaNotificationList.presets.filter { !existing.contains($0.lowercased()) }, id: \.self) { name in
                        Button(name) { onAdd(name) }
                    }
                } header: {
                    Text("Common apps")
                }
            }
            .navigationTitle("Add an app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func canAdd(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !WenaNotificationList.nameBytes(trimmed).isEmpty && !existing.contains(trimmed.lowercased())
    }

    private func addCustom() {
        guard canAdd(custom) else { return }
        onAdd(custom.trimmingCharacters(in: .whitespaces))
    }
}

#Preview("Notifications") {
    @Previewable @State var apps = WenaNotificationList.defaultList()
    NavigationStack {
        NotificationAppsView(apps: apps, status: .sent(at: Date()), onChange: { apps = $0 })
    }
}
