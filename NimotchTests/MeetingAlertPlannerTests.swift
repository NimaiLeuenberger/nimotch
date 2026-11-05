import Foundation
import Testing
@testable import nimotch

@Suite("Meeting alerts: reminder, countdown, start")
struct MeetingAlertPlannerTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func meeting(_ id: String, inMinutes minutes: Double, allDay: Bool = false, declined: Bool = false) -> CalendarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarEvent(id: id, title: id, start: start, end: start.addingTimeInterval(1800),
                             isAllDay: allDay, isDeclined: declined)
    }

    func plan(_ events: [CalendarEvent], settings: MeetingAlertPlanner.Settings = .init(),
              reminded: Set<String> = [], announced: Set<String> = []) -> MeetingAlertPlanner.Plan {
        MeetingAlertPlanner.plan(events: events, now: now, settings: settings, reminded: reminded, announced: announced)
    }

    @Test func remindsBetween30And10MinutesBefore() {
        #expect(plan([meeting("a", inMinutes: 20)]).reminders.map(\.id) == ["a"])
        #expect(plan([meeting("a", inMinutes: 30)]).reminders.map(\.id) == ["a"])
        #expect(plan([meeting("a", inMinutes: 31)]).reminders.isEmpty)
        #expect(plan([meeting("a", inMinutes: 9)]).reminders.isEmpty)
    }

    @Test func remindsOnlyOnceAndRespectsSetting() {
        #expect(plan([meeting("a", inMinutes: 20)], reminded: ["a"]).reminders.isEmpty)
        #expect(plan([meeting("a", inMinutes: 20)], settings: .init(remindBefore: false)).reminders.isEmpty)
    }

    @Test func countsDownFrom10Minutes() {
        #expect(plan([meeting("a", inMinutes: 9)]).countdown?.id == "a")
        #expect(plan([meeting("a", inMinutes: 11)]).countdown == nil)
        #expect(plan([meeting("a", inMinutes: 9)], settings: .init(showCountdown: false)).countdown == nil)
    }

    @Test func showsNowForConfiguredMinutes() {
        let started = meeting("a", inMinutes: -1.5)
        #expect(plan([started], settings: .init(nowMinutes: 2)).countdown?.id == "a")
        #expect(plan([started], settings: .init(nowMinutes: 1)).countdown == nil)
        #expect(plan([meeting("a", inMinutes: -0.2)], settings: .init(nowMinutes: 0)).countdown == nil)
    }

    @Test func hiddenCountdownStillAnnouncesStart() {
        let settings = MeetingAlertPlanner.Settings(hiddenCountdowns: ["a"])
        #expect(plan([meeting("a", inMinutes: 5)], settings: settings).countdown == nil)
        let atStart = plan([meeting("a", inMinutes: -0.2)], settings: settings)
        #expect(atStart.countdown == nil)
        #expect(atStart.starting.map(\.id) == ["a"])
    }

    @Test func announcesStartOnceWithinFirstMinute() {
        #expect(plan([meeting("a", inMinutes: -0.5)]).starting.map(\.id) == ["a"])
        #expect(plan([meeting("a", inMinutes: -0.5)], announced: ["a"]).starting.isEmpty)
        #expect(plan([meeting("a", inMinutes: -2)]).starting.isEmpty)
        #expect(plan([meeting("a", inMinutes: 0.5)]).starting.isEmpty)
    }

    @Test func ignoresAllDayAndDeclined() {
        let p = plan([meeting("allday", inMinutes: 5, allDay: true), meeting("declined", inMinutes: 5, declined: true)])
        #expect(p.countdown == nil)
        #expect(p.reminders.isEmpty)
    }

    @Test func prefersUpcomingMeetingOverOneThatStarted() {
        let p = plan([meeting("started", inMinutes: -1), meeting("next", inMinutes: 5)])
        #expect(p.countdown?.id == "next")
    }

    @Test func ticksFastOnlyNearAMeeting() {
        #expect(plan([meeting("a", inMinutes: 10.5)]).nextTick == .seconds(1))
        #expect(plan([meeting("a", inMinutes: 25)]).nextTick == .seconds(15))
        #expect(plan([]).nextTick == .seconds(15))
    }
}
