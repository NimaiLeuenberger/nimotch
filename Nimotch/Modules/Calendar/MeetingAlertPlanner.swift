import Foundation

/// Pure decision logic for meeting alerts (no side effects, unit-tested).
/// `MeetingAlertScheduler` runs it every tick and applies the result to the notch.
///
/// Timeline per meeting:
/// - T-30 … T-10 min: one reminder peek
/// - T-10 min … start + `nowMinutes`: countdown in the wings (unless hidden)
/// - start … start + 60 s: one "is starting" peek (with Join)
enum MeetingAlertPlanner {
    static let reminderLead: TimeInterval = 30 * 60
    static let countdownLead: TimeInterval = 10 * 60
    static let startWindow: TimeInterval = 60

    struct Settings: Equatable {
        var remindBefore = true
        var showCountdown = true
        var nowMinutes = 2
        var hiddenCountdowns: Set<String> = []
    }

    struct Plan: Equatable {
        /// Meetings that need a "in N min" reminder now (not yet reminded).
        var reminders: [CalendarEvent] = []
        /// Meetings that just started (not yet announced).
        var starting: [CalendarEvent] = []
        /// Meeting to count down in the wings, if any.
        var countdown: CalendarEvent?
        /// When to evaluate again: every second near a countdown, else every 15 s.
        var nextTick: Duration = .seconds(15)
    }

    static func plan(
        events: [CalendarEvent],
        now: Date,
        settings: Settings,
        reminded: Set<String>,
        announced: Set<String>
    ) -> Plan {
        let meetings = events.filter { !$0.isAllDay && !$0.isDeclined }
        var plan = Plan()

        if settings.remindBefore {
            plan.reminders = meetings.filter {
                let lead = $0.start.timeIntervalSince(now)
                return lead > countdownLead && lead <= reminderLead && !reminded.contains($0.id)
            }
        }

        plan.starting = meetings.filter {
            let sinceStart = now.timeIntervalSince($0.start)
            return sinceStart >= 0 && sinceStart < startWindow && !announced.contains($0.id)
        }

        let tail = TimeInterval(settings.nowMinutes * 60)
        if settings.showCountdown {
            let inWindow = meetings.filter {
                let lead = $0.start.timeIntervalSince(now)
                return lead <= countdownLead && lead > -tail && !settings.hiddenCountdowns.contains($0.id)
            }
            // Prefer the next upcoming meeting; otherwise the one that started most recently.
            plan.countdown = inWindow.first { $0.start > now } ?? inWindow.last
        }

        let soon = meetings.contains {
            let lead = $0.start.timeIntervalSince(now)
            return lead <= countdownLead + 60 && lead > -max(tail, startWindow)
        }
        plan.nextTick = soon ? .seconds(1) : .seconds(15)
        return plan
    }
}
