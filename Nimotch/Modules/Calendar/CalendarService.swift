import AppKit
import EventKit
import SwiftUI

/// Today's events from every calendar in Calendar.app (incl. the Outlook/Exchange account).
/// Reloads on EventKit change notifications, day change and wake — no polling.
@MainActor
@Observable
final class CalendarService {
    enum Access { case notDetermined, granted, denied }

    struct CalendarInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let source: String
        let color: Color
    }

    private(set) var access: Access
    private(set) var events: [CalendarEvent] = []
    private(set) var calendars: [CalendarInfo] = []

    var excludedCalendarIDs: Set<String> {
        didSet { defaults.set(Array(excludedCalendarIDs), forKey: Keys.excluded); reload() }
    }
    var showAllDay: Bool {
        didSet { defaults.set(showAllDay, forKey: Keys.allDay); reload() }
    }
    var alertBeforeMeeting: Bool {
        didSet { defaults.set(alertBeforeMeeting, forKey: Keys.alert30) }
    }
    var showCountdown: Bool {
        didSet { defaults.set(showCountdown, forKey: Keys.countdown) }
    }
    /// How long the wings show "now" after a meeting started (0 = not at all).
    var nowMinutes: Int {
        didSet { defaults.set(nowMinutes, forKey: Keys.nowMinutes) }
    }
    /// Events whose countdown the user hid (the start peek with Join still appears).
    private(set) var hiddenCountdowns: Set<String> = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let excluded = "calendar.excludedIDs"
        static let allDay = "calendar.showAllDay"
        static let alert30 = "calendar.alertBeforeMeeting"
        static let countdown = "calendar.showCountdown"
        static let nowMinutes = "calendar.nowMinutes"
    }

    init() {
        defaults.register(defaults: [Keys.allDay: true, Keys.alert30: true, Keys.countdown: true, Keys.nowMinutes: 2])
        access = Self.currentAccess()
        excludedCalendarIDs = Set(defaults.stringArray(forKey: Keys.excluded) ?? [])
        showAllDay = defaults.bool(forKey: Keys.allDay)
        alertBeforeMeeting = defaults.bool(forKey: Keys.alert30)
        showCountdown = defaults.bool(forKey: Keys.countdown)
        nowMinutes = defaults.integer(forKey: Keys.nowMinutes)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        reload()
    }

    func hideCountdown(for eventID: String) {
        hiddenCountdowns.insert(eventID)
    }

    func requestAccessIfNeeded() async {
        guard access == .notDetermined else { return }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        access = granted ? .granted : .denied
        reload()
    }

    func reload() {
        access = Self.currentAccess()
        guard access == .granted else {
            events = []
            calendars = []
            return
        }
        let all = store.calendars(for: .event)
        calendars = all
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "Other", color: Color(nsColor: $0.color)) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }

        let included = all.filter { !excludedCalendarIDs.contains($0.calendarIdentifier) }
        guard !included.isEmpty else { events = []; return }

        let dayStart = Calendar.current.startOfDay(for: .now)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: included)
        events = store.events(matching: predicate)
            .map(CalendarEvent.init)
            .filter { showAllDay || !$0.isAllDay }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start, $0.title) < ($1.isAllDay ? 0 : 1, $1.start, $1.title) }
    }

    func openInCalendarApp(_ event: CalendarEvent) {
        if let id = event.eventIdentifier,
           let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
    }

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
