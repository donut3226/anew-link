import SwiftUI

/// Tick which of the phone's calendars go to the band. Each change sends the calendar again.
struct CalendarChoicesView: View {
    let choices: [CalendarChoice]
    let onToggle: (String, Bool) -> Void

    private var accounts: [String] {
        var seen = Set<String>()
        return choices.map(\.account).filter { seen.insert($0).inserted }
    }

    var body: some View {
        List {
            ForEach(accounts, id: \.self) { account in
                Section(account.isEmpty ? "Calendars" : account) {
                    ForEach(choices.filter { $0.account == account }) { choice in
                        Toggle(choice.title, isOn: Binding(get: { choice.isIncluded },
                                                           set: { onToggle(choice.id, $0) }))
                    }
                }
            }
            Section {
            } footer: {
                Text("Only events from ticked calendars are sent. New calendars are ticked until you switch them off.")
            }
        }
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Calendars") {
    NavigationStack {
        CalendarChoicesView(choices: [
            CalendarChoice(id: "1", title: "Home", account: "iCloud", isIncluded: true),
            CalendarChoice(id: "2", title: "Work", account: "iCloud", isIncluded: false),
            CalendarChoice(id: "3", title: "Holidays", account: "Other", isIncluded: true),
        ], onToggle: { _, _ in })
    }
}
