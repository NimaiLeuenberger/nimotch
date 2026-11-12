import SwiftUI

/// Fans module output (peeks, live activities) out to the notch on every enabled display,
/// and remembers it so a notch created later (display plugged in) starts in the same state.
/// Modules talk to the hub; each `NotchViewModel` keeps its own open/closed/hover state.
@MainActor
@Observable
final class NotchHub {
    /// One view model per enabled display, built-in first (the "primary" notch).
    private(set) var notches: [NotchViewModel] = []
    private(set) var demoWings = false
    @ObservationIgnored private var music: NotchViewModel.MusicActivity?
    @ObservationIgnored private var meetingCountdown: NotchViewModel.MeetingCountdown?

    @ObservationIgnored var openSettings: (() -> Void)?
    /// Hides the countdown for an event (wired to CalendarService).
    @ObservationIgnored var onStopCountdown: ((String) -> Void)?

    var isAnyExpanded: Bool { notches.contains { $0.mode == .expanded } }

    /// Creates a notch view model for a new display, already showing the current state.
    func makeNotch() -> NotchViewModel {
        let notch = NotchViewModel()
        notch.openSettings = { [weak self] in self?.openSettings?() }
        notch.onStopCountdown = { [weak self] id in self?.stopCountdown(id) }
        notch.setMusic(music)
        notch.setMeetingCountdown(meetingCountdown)
        notch.setDemoWings(demoWings)
        return notch
    }

    func setNotches(_ notches: [NotchViewModel]) { self.notches = notches }

    // MARK: Broadcast

    func showPeek(_ peek: NotchViewModel.Peek) {
        notches.forEach { $0.showPeek(peek) }
    }

    func setMusic(_ activity: NotchViewModel.MusicActivity?) {
        music = activity
        notches.forEach { $0.setMusic(activity) }
    }

    func setMeetingCountdown(_ countdown: NotchViewModel.MeetingCountdown?) {
        meetingCountdown = countdown
        notches.forEach { $0.setMeetingCountdown(countdown) }
    }

    func setDemoWings(_ on: Bool) {
        demoWings = on
        notches.forEach { $0.setDemoWings(on) }
    }

    func stopCountdown(_ eventID: String) {
        onStopCountdown?(eventID)
        setMeetingCountdown(nil)
    }

    /// Menu bar "Open/Collapse notch": acts on the primary notch.
    func toggleFromMenu() { notches.first?.toggleFromMenu() }
}
