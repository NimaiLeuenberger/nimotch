import EventKit
import SwiftUI

/// Value snapshot of an EKEvent, safe to keep around in view state.
struct CalendarEvent: Identifiable, Equatable {
    enum ResponseStatus { case accepted, declined, tentative, pending, unknown }

    struct Attendee: Equatable, Hashable {
        let name: String
        let status: ResponseStatus
        let isCurrentUser: Bool
    }

    let id: String
    let eventIdentifier: String?
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let color: Color
    let location: String?
    let notes: String?
    let url: URL?
    let organizer: String?
    let attendees: [Attendee]
    let meetingLink: MeetingLink?
    let isDeclined: Bool

    /// Memberwise init (tests, previews).
    init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
         calendarTitle: String = "Calendar", color: Color = .blue, location: String? = nil,
         notes: String? = nil, url: URL? = nil, organizer: String? = nil,
         attendees: [Attendee] = [], meetingLink: MeetingLink? = nil, isDeclined: Bool = false) {
        self.id = id
        eventIdentifier = nil
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.color = color
        self.location = location
        self.notes = notes
        self.url = url
        self.organizer = organizer
        self.attendees = attendees
        self.meetingLink = meetingLink
        self.isDeclined = isDeclined
    }

    init(_ event: EKEvent) {
        id = "\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)"
        eventIdentifier = event.eventIdentifier
        title = event.title?.isEmpty == false ? event.title : "(No title)"
        start = event.startDate
        end = event.endDate
        isAllDay = event.isAllDay
        calendarTitle = event.calendar?.title ?? ""
        color = event.calendar.map { Color(nsColor: $0.color) } ?? .gray
        location = event.location?.nilIfBlank
        notes = event.notes.map(Self.cleanNotes)?.nilIfBlank
        url = event.url
        organizer = event.organizer.map(Self.displayName)
        attendees = (event.attendees ?? []).map {
            Attendee(name: Self.displayName($0), status: Self.status($0.participantStatus), isCurrentUser: $0.isCurrentUser)
        }
        isDeclined = attendees.contains { $0.isCurrentUser && $0.status == .declined }
        meetingLink = LinkDetector.find(in: [event.url?.absoluteString, event.location, event.notes])
    }

    func isOngoing(at now: Date) -> Bool { start <= now && now < end }

    var timeRange: String {
        if isAllDay { return "All day" }
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    private static func displayName(_ p: EKParticipant) -> String {
        if let name = p.name?.nilIfBlank { return name }
        let spec = p.url.absoluteString
        return spec.hasPrefix("mailto:") ? String(spec.dropFirst(7)) : spec
    }

    private static func status(_ s: EKParticipantStatus) -> ResponseStatus {
        switch s {
        case .accepted: .accepted
        case .declined: .declined
        case .tentative: .tentative
        case .pending: .pending
        default: .unknown
        }
    }

    /// Trim Outlook/Teams boilerplate whitespace.
    private static func cleanNotes(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"\n[ \t]*\n(\s*\n)+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
