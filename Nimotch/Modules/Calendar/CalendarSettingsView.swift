import SwiftUI

struct CalendarSettingsView: View {
    @Bindable var calendar: CalendarService

    var body: some View {
        Section("Calendar") {
            switch calendar.access {
            case .notDetermined:
                Button("Allow Calendar Access") { Task { await calendar.requestAccessIfNeeded() } }
            case .denied:
                HStack {
                    Text("Calendar access is off.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Open System Settings") { NSWorkspace.shared.open(CalendarService.privacySettingsURL) }
                }
            case .granted:
                Toggle("Show all-day events", isOn: $calendar.showAllDay)
                Toggle("Alert 30 min before a meeting", isOn: $calendar.alertBeforeMeeting)
                Toggle("Countdown in the notch from 10 min before", isOn: $calendar.showCountdown)
                Picker("Show \u{201C}now\u{201D} after the start for", selection: $calendar.nowMinutes) {
                    Text("Don't show").tag(0)
                    Text("1 min").tag(1)
                    Text("2 min").tag(2)
                    Text("3 min").tag(3)
                    Text("5 min").tag(5)
                }
                .disabled(!calendar.showCountdown)
            }
        }
        if calendar.access == .granted {
            let sources = Dictionary(grouping: calendar.calendars, by: \.source)
            ForEach(sources.keys.sorted(), id: \.self) { source in
                Section(source) {
                    ForEach(sources[source] ?? []) { info in
                        Toggle(isOn: Binding(
                            get: { !calendar.excludedCalendarIDs.contains(info.id) },
                            set: { on in
                                if on { calendar.excludedCalendarIDs.remove(info.id) }
                                else { calendar.excludedCalendarIDs.insert(info.id) }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Circle().fill(info.color).frame(width: 8, height: 8)
                                Text(info.title)
                            }
                        }
                    }
                }
            }
        }
    }
}
