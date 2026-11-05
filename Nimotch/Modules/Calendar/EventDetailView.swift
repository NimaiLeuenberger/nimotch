import SwiftUI

struct EventDetailView: View {
    @Environment(CalendarService.self) private var calendar
    let event: CalendarEvent
    let onBack: () -> Void
    @State private var showAllAttendees = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if let location = event.location {
                        InfoLine(icon: "mappin.and.ellipse", text: location)
                    }
                    if let organizer = event.organizer {
                        InfoLine(icon: "person.crop.circle", text: "Organizer: \(organizer)")
                    }
                    if !event.attendees.isEmpty { attendees }
                    if let notes = event.notes {
                        Divider().overlay(.white.opacity(0.08))
                        Text(notes)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Label("Today", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if let link = event.meetingLink {
                JoinButton(link: link)
            }
            Button {
                calendar.openInCalendarApp(event)
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in Calendar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .strikethrough(event.isDeclined)
                    .textSelection(.enabled)
                Text("\(event.timeRange) · \(event.calendarTitle)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var attendees: some View {
        let accepted = event.attendees.filter { $0.status == .accepted }.count
        let shown = showAllAttendees ? event.attendees : Array(event.attendees.prefix(6))
        return VStack(alignment: .leading, spacing: 4) {
            InfoLine(icon: "person.2", text: "\(event.attendees.count) attendees · \(accepted) accepted")
            ForEach(shown, id: \.self) { attendee in
                HStack(spacing: 6) {
                    statusIcon(attendee.status)
                    Text(attendee.name + (attendee.isCurrentUser ? " (you)" : ""))
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 22)
            }
            if event.attendees.count > 6 {
                Button(showAllAttendees ? "Show less" : "Show all \(event.attendees.count)") {
                    showAllAttendees.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.leading, 22)
            }
        }
    }

    private func statusIcon(_ status: CalendarEvent.ResponseStatus) -> some View {
        let (name, color): (String, Color) = switch status {
        case .accepted: ("checkmark.circle.fill", .green)
        case .declined: ("xmark.circle.fill", .red)
        case .tentative: ("questionmark.circle.fill", .orange)
        case .pending, .unknown: ("circle", .secondary)
        }
        return Image(systemName: name).foregroundStyle(color).font(.system(size: 10))
    }
}

private struct InfoLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(text)
                .textSelection(.enabled)
        }
        .font(.system(size: 12))
    }
}
