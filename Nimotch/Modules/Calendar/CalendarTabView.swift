import SwiftUI

struct CalendarTabView: View {
    @Environment(CalendarService.self) private var calendar
    let notch: NotchViewModel
    @State private var selectedID: String?
    @State private var selectedSnapshot: CalendarEvent?

    var body: some View {
        switch calendar.access {
        case .notDetermined:
            AccessPrompt(
                text: "nimotch needs access to your calendars to show today's meetings.",
                buttonTitle: "Allow Calendar Access"
            ) {
                notch.pin()
                Task { await calendar.requestAccessIfNeeded() }
            }
        case .denied:
            AccessPrompt(
                text: "Calendar access is off. Turn on nimotch under Privacy & Security → Calendars.",
                buttonTitle: "Open System Settings"
            ) {
                NSWorkspace.shared.open(CalendarService.privacySettingsURL)
            }
        case .granted:
            if let event = selectedEvent {
                EventDetailView(event: event) {
                    withAnimation(.snappy) { selectedID = nil }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                EventListView(notch: notch) { event in
                    notch.pin()
                    selectedSnapshot = event
                    withAnimation(.snappy) { selectedID = event.id }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    /// Latest version of the selected event (falls back to the snapshot if it was deleted).
    private var selectedEvent: CalendarEvent? {
        guard let selectedID else { return nil }
        return calendar.events.first { $0.id == selectedID } ?? selectedSnapshot
    }
}

private struct AccessPrompt: View {
    let text: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
