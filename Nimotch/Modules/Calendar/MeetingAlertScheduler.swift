import SwiftUI

/// Runs `MeetingAlertPlanner` on a timer and applies its plan to the notch
/// (reminder peeks, countdown wings, "is starting" peek with Join).
@MainActor
final class MeetingAlertScheduler {
    private let calendar: CalendarService
    private let notch: NotchViewModel
    private var task: Task<Void, Never>?
    private var reminded: Set<String> = []
    private var announced: Set<String> = []

    init(calendar: CalendarService, notch: NotchViewModel) {
        self.calendar = calendar
        self.notch = notch
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.tick() else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    deinit { task?.cancel() }

    /// Evaluates alerts for `now` and returns how long to wait until the next tick.
    @discardableResult
    func tick(now: Date = .now) -> Duration {
        let plan = MeetingAlertPlanner.plan(
            events: calendar.events,
            now: now,
            settings: .init(
                remindBefore: calendar.alertBeforeMeeting,
                showCountdown: calendar.showCountdown,
                nowMinutes: calendar.nowMinutes,
                hiddenCountdowns: calendar.hiddenCountdowns
            ),
            reminded: reminded,
            announced: announced
        )

        for event in plan.reminders {
            reminded.insert(event.id)
            let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded())
            notch.showPeek(.init(
                icon: "calendar",
                tint: event.color,
                title: "\(event.title) in \(minutes) min",
                subtitle: subtitle(for: event),
                duration: .seconds(6)
            ))
        }

        for event in plan.starting {
            announced.insert(event.id)
            notch.showPeek(.init(
                icon: "video.fill",
                tint: .green,
                title: "\(event.title) is starting",
                subtitle: subtitle(for: event),
                duration: .seconds(event.meetingLink == nil ? 6 : 15),
                action: event.meetingLink.map { link in
                    .init(title: "Join", icon: "video.fill") { link.open() }
                }
            ))
        }

        notch.setMeetingCountdown(plan.countdown.map {
            .init(eventID: $0.id, title: $0.title, start: $0.start, color: $0.color)
        })
        return plan.nextTick
    }

    private func subtitle(for event: CalendarEvent) -> String {
        [event.timeRange, event.meetingLink?.service.rawValue ?? event.location]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
