import SwiftUI

/// Today's remaining events (ongoing + upcoming), scrollable.
struct EventListView: View {
    @Environment(CalendarService.self) private var calendar
    let notch: NotchViewModel
    let onSelect: (CalendarEvent) -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let allDay = calendar.events.filter(\.isAllDay)
            let timed = calendar.events.filter { !$0.isAllDay && $0.end > now }

            if allDay.isEmpty && timed.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(.green.opacity(0.8))
                    Text("No more events today")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        if !allDay.isEmpty {
                            AllDayStrip(events: allDay, onSelect: onSelect)
                        }
                        ForEach(timed) { event in
                            EventRow(
                                event: event,
                                now: now,
                                countdownActive: notch.meetingCountdown?.eventID == event.id,
                                hideCountdown: {
                                    calendar.hideCountdown(for: event.id)
                                    notch.setMeetingCountdown(nil)
                                }
                            ) { onSelect(event) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.automatic)
            }
        }
    }
}

private struct AllDayStrip: View {
    let events: [CalendarEvent]
    let onSelect: (CalendarEvent) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(events) { event in
                    Button { onSelect(event) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(event.color).frame(width: 6, height: 6)
                            Text(event.title).lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(event.color.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.never)
    }
}

struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    var countdownActive = false
    var hideCountdown: () -> Void = {}
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(event.color)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .strikethrough(event.isDeclined)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(event.timeRange)
                        if let location = event.location, event.meetingLink == nil || !location.contains("http") {
                            Text("·")
                            Text(location).lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .opacity(event.isDeclined ? 0.5 : 1)
                Spacer(minLength: 6)
                if countdownActive {
                    Button(action: hideCountdown) {
                        Image(systemName: "timer.slash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Hide the countdown for this meeting")
                }
                badge
                if let link = event.meetingLink {
                    JoinButton(link: link, prominent: isJoinable)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(hovering ? 0.12 : 0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    /// Ongoing, or starting within 15 minutes.
    private var isJoinable: Bool {
        event.isOngoing(at: now) || event.start.timeIntervalSince(now) <= 15 * 60
    }

    @ViewBuilder private var badge: some View {
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if event.isOngoing(at: now) {
            Pill(text: "now", color: .green)
        } else if minutes < 60 {
            Pill(text: minutes < 1 ? "in <1 min" : "in \(minutes) min", color: .orange)
        }
    }
}

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.22)))
            .foregroundStyle(color)
    }
}

struct JoinButton: View {
    let link: MeetingLink
    var prominent = true

    var body: some View {
        Button { link.open() } label: {
            Label(prominent ? "Join" : link.service.rawValue, systemImage: "video.fill")
                .font(.system(size: 11, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(prominent ? Color.green.opacity(0.85) : .white.opacity(0.1)))
                .foregroundStyle(prominent ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .help("Open in \(link.service.rawValue)")
    }
}
