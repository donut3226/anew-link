import SwiftUI

/// Plain-words text for alarms. Pure, so it can be tested.
nonisolated enum AlarmText {

    /// "Once", "Every day", "Weekdays", "Weekends", or short day names like "Mon, Wed, Fri".
    static func days(_ days: Set<Int>, calendar: Calendar = .current) -> String {
        switch days {
        case []: return "Once"
        case Set(1...7): return "Every day"
        case [2, 3, 4, 5, 6]: return "Weekdays"
        case [1, 7]: return "Weekends"
        default:
            return orderedWeekdays(calendar: calendar)
                .filter { days.contains($0) }
                .map { calendar.shortWeekdaySymbols[$0 - 1] }
                .joined(separator: ", ")
        }
    }

    /// Weekday numbers (1 Sunday ... 7 Saturday) starting from the user's first day of the week.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// The time in the user's 12 or 24 hour style.
    static func time(hour: Int, minute: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Add or edit one alarm (shown as a sheet).
struct AlarmEditor: View {
    let isNew: Bool
    let onSave: (BandAlarm) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var alarm: BandAlarm
    @State private var time: Date

    init(alarm: BandAlarm, isNew: Bool, onSave: @escaping (BandAlarm) -> Void,
         onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _alarm = State(initialValue: alarm)
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: alarm.hour, minute: alarm.minute)) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                Section {
                    ForEach(AlarmText.orderedWeekdays(), id: \.self) { day in
                        Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(
                            get: { alarm.repeatDays.contains(day) },
                            set: { on in
                                if on { alarm.repeatDays.insert(day) } else { alarm.repeatDays.remove(day) }
                            }
                        ))
                    }
                } header: {
                    Text("Repeat")
                } footer: {
                    Text("No days ticked: the alarm goes off once.")
                }

                Section {
                    Toggle("Smart wake-up", isOn: Binding(
                        get: { alarm.smartWakeupMinutes > 0 },
                        set: { alarm.smartWakeupMinutes = $0 ? BandAlarm.defaultSmartWakeupMinutes : 0 }
                    ))
                } footer: {
                    Text("The band may vibrate up to \(BandAlarm.defaultSmartWakeupMinutes) minutes early, when you're in light sleep. Needs the band on your wrist.")
                }

                if !isNew {
                    Section {
                        Button("Delete alarm", role: .destructive, action: onDelete)
                    }
                }
            }
            .navigationTitle(isNew ? "New alarm" : "Edit alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        alarm.hour = parts.hour ?? alarm.hour
                        alarm.minute = parts.minute ?? alarm.minute
                        alarm.isOn = true
                        onSave(alarm)
                    }
                }
            }
        }
    }
}

#Preview("New alarm") {
    AlarmEditor(alarm: BandAlarm(), isNew: true, onSave: { _ in }, onDelete: {}, onCancel: {})
}
