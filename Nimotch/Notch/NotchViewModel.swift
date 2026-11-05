import SwiftUI

/// State machine for the notch: collapsed ⇄ peek ⇄ expanded.
@MainActor
@Observable
final class NotchViewModel {
    enum Mode: Equatable { case collapsed, peek, expanded }

    // MARK: State
    private(set) var mode: Mode = .collapsed
    private(set) var isPinned = false
    private(set) var peek: Peek?
    private(set) var demoWings = false
    private(set) var meetingCountdown: MeetingCountdown?
    private(set) var music: MusicActivity?
    /// Mouse rested 2 s on the countdown: it turns into a stop button.
    private(set) var countdownStopArmed = false
    var selectedTab: Tab = .calendar
    var geometry: NotchGeometry? { didSet { layoutDidChange?() } }

    /// Called whenever the visible shape changes size, so the window can update hit-testing.
    @ObservationIgnored var layoutDidChange: (() -> Void)?
    /// Hides the countdown for an event (wired to CalendarService).
    @ObservationIgnored var onStopCountdown: ((String) -> Void)?
    @ObservationIgnored private var isOverTrailingWing = false
    @ObservationIgnored private var armTask: Task<Void, Never>?
    static let stopArmDelay: Duration = .seconds(2)
    /// Opens the settings window.
    @ObservationIgnored var openSettings: (() -> Void)?
    /// Makes the panel the key window so text fields receive typing.
    @ObservationIgnored var requestKeyFocus: (() -> Void)?

    /// Mouse is over the notch. Collapsed/peek: the shape grows slightly and glows.
    private(set) var isHovering = false
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?

    private let animation = Animation.spring(response: 0.38, dampingFraction: 0.82)
    /// How much the collapsed notch grows on hover.
    static let hoverGrowth = CGSize(width: 16, height: 4)
    static let hoverCloseDelay: Duration = .milliseconds(300)

    // MARK: Layout
    var notchSize: CGSize { geometry?.notchSize ?? CGSize(width: 200, height: 32) }
    var wingWidth: CGFloat { (notchSize.height * 1.5).rounded() }
    /// Highest-priority live activity (meeting countdown beats everything else).
    var liveActivity: LiveActivity? {
        if let meetingCountdown { return .meeting(meetingCountdown) }
        if let music { return .music(music) }
        return demoWings ? .demo : nil
    }
    var hasWings: Bool { liveActivity != nil }

    var topRadius: CGFloat { mode == .collapsed ? 6 : 10 }
    var bottomRadius: CGFloat {
        switch mode {
        case .collapsed: 9
        case .peek: 18
        case .expanded: 26
        }
    }

    /// Size of the black body (without the top ears).
    var bodySize: CGSize {
        let notch = notchSize
        switch mode {
        case .collapsed:
            let grow = isHovering ? Self.hoverGrowth : .zero
            return CGSize(width: notch.width + (hasWings ? 2 * wingWidth : 0) + grow.width,
                          height: notch.height + grow.height)
        case .peek:
            return CGSize(width: max(notch.width + 2 * wingWidth, 420), height: notch.height + 50)
        case .expanded:
            return CGSize(width: 640, height: 340)
        }
    }

    /// Full frame of the shape including the top ears.
    var shapeSize: CGSize {
        CGSize(width: bodySize.width + 2 * topRadius, height: bodySize.height)
    }

    /// Largest size the shape can take (used to size the window).
    static let canvasSize = CGSize(width: 740, height: 410)

    // MARK: Input
    func mouseMoved(inside: Bool) {
        guard inside != isHovering else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isHovering = inside }
        if mode == .collapsed { layoutDidChange?() }
        hoverTask?.cancel()
        if inside {
            // Hover only hints (grow + glow); a click expands. Hovering a peek holds it.
            if mode == .peek { peekTask?.cancel() }
        } else if mode == .peek, let current = peek {
            schedulePeekDismissal(for: current, after: .seconds(2))
        } else if mode == .expanded, !isPinned {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: Self.hoverCloseDelay)
                guard !Task.isCancelled, let self, !self.isHovering, !self.isPinned else { return }
                self.collapse()
            }
        }
    }

    /// A click on the notch itself: expand. It closes again when the mouse leaves (unless pinned).
    func tapNotch() {
        hoverTask?.cancel()
        guard mode != .expanded else { return }
        expand()
    }

    func pin() { isPinned = true }

    /// Call before inline text editing: keeps the panel open and gives it keyboard focus.
    func beginTextEditing() {
        isPinned = true
        requestKeyFocus?()
    }

    func togglePinned() {
        isPinned.toggle()
        if !isPinned, !isHovering { collapse() }
    }

    /// A click anywhere outside nimotch.
    func clickedOutside() {
        guard mode == .expanded else { return }
        isPinned = false
        collapse()
    }

    func toggleFromMenu() {
        if mode == .expanded {
            isPinned = false
            collapse()
        } else {
            isPinned = true
            tapNotch()
        }
    }

    // MARK: Peek & wings
    func showPeek(_ newPeek: Peek) {
        peekTask?.cancel()
        withAnimation(animation) {
            peek = newPeek
            if mode == .collapsed { mode = .peek }
        }
        layoutDidChange?()
        schedulePeekDismissal(for: newPeek, after: newPeek.duration)
    }

    private func schedulePeekDismissal(for target: Peek, after delay: Duration) {
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.peek?.id == target.id else { return }
            self.dismissPeek()
        }
    }

    func dismissPeek() {
        peekTask?.cancel()
        withAnimation(animation) {
            peek = nil
            if mode == .peek { mode = .collapsed }
        }
        layoutDidChange?()
    }

    func setDemoWings(_ on: Bool) {
        withAnimation(animation) { demoWings = on }
        layoutDidChange?()
    }

    func setMusic(_ activity: MusicActivity?) {
        guard activity != music else { return }
        withAnimation(animation) { music = activity }
        layoutDidChange?()
    }

    /// Mouse entered/left the trailing wing (computed by the window controller).
    func trailingWingHover(_ over: Bool) {
        guard over != isOverTrailingWing else { return }
        isOverTrailingWing = over
        armTask?.cancel()
        if over, mode == .collapsed, meetingCountdown != nil {
            armTask = Task { [weak self] in
                try? await Task.sleep(for: Self.stopArmDelay)
                guard !Task.isCancelled, let self, self.isOverTrailingWing else { return }
                withAnimation(.snappy) { self.countdownStopArmed = true }
            }
        } else if countdownStopArmed {
            withAnimation(.snappy) { countdownStopArmed = false }
        }
    }

    func stopCountdown() {
        guard let countdown = meetingCountdown else { return }
        onStopCountdown?(countdown.eventID)
        setMeetingCountdown(nil)
    }

    func setMeetingCountdown(_ countdown: MeetingCountdown?) {
        guard countdown != meetingCountdown else { return }
        if countdown == nil { countdownStopArmed = false }
        withAnimation(animation) { meetingCountdown = countdown }
        layoutDidChange?()
    }

    // MARK: Transitions
    private func expand() {
        peekTask?.cancel()
        // Open the tab for whatever the wings are showing.
        switch liveActivity {
        case .meeting: selectedTab = .calendar
        case .music: selectedTab = .spotify
        case .demo, nil: break
        }
        withAnimation(animation) {
            peek = nil
            mode = .expanded
        }
        layoutDidChange?()
    }

    private func collapse() {
        withAnimation(animation) { mode = .collapsed }
        layoutDidChange?()
    }
}
