import Foundation
import Testing
@testable import nimotch

@MainActor
@Suite("Notch state machine")
struct NotchViewModelTests {
    let notch = NotchViewModel()

    @Test func startsCollapsedAtNotchSize() {
        #expect(notch.mode == .collapsed)
        #expect(notch.bodySize == notch.notchSize)
        #expect(notch.shapeSize.width == notch.notchSize.width + 2 * notch.topRadius)
    }

    @Test func hoverOnlyGrowsSlightly() {
        notch.mouseMoved(inside: true)
        #expect(notch.mode == .collapsed)
        #expect(notch.isHovering)
        #expect(notch.bodySize.width == notch.notchSize.width + NotchViewModel.hoverGrowth.width)
        notch.mouseMoved(inside: false)
        #expect(notch.bodySize == notch.notchSize)
    }

    @Test func clickExpandsAndLeavingCollapses() async throws {
        notch.mouseMoved(inside: true)
        notch.tapNotch()
        #expect(notch.mode == .expanded)
        notch.mouseMoved(inside: false)
        try await Task.sleep(for: NotchViewModel.hoverCloseDelay + .milliseconds(200))
        #expect(notch.mode == .collapsed)
    }

    @Test func pinnedStaysOpenUntilClickOutside() async throws {
        notch.tapNotch()
        notch.pin()
        notch.mouseMoved(inside: true)
        notch.mouseMoved(inside: false)
        try await Task.sleep(for: NotchViewModel.hoverCloseDelay + .milliseconds(200))
        #expect(notch.mode == .expanded)
        notch.clickedOutside()
        #expect(notch.mode == .collapsed)
        #expect(!notch.isPinned)
    }

    @Test func peekShowsAndDismisses() {
        notch.showPeek(.init(icon: "bell", title: "Hi"))
        #expect(notch.mode == .peek)
        #expect(notch.peek?.title == "Hi")
        notch.dismissPeek()
        #expect(notch.mode == .collapsed)
        #expect(notch.peek == nil)
    }

    @Test func peekDoesNotInterruptExpandedPanel() {
        notch.tapNotch()
        notch.showPeek(.init(icon: "bell", title: "Hi"))
        #expect(notch.mode == .expanded)
    }

    @Test func liveActivityPriorityMeetingThenMusicThenDemo() {
        notch.setDemoWings(true)
        #expect(notch.liveActivity == .demo)
        notch.setMusic(.init(trackID: "t", artworkURL: nil))
        #expect(notch.liveActivity == .music(.init(trackID: "t", artworkURL: nil)))
        let meeting = NotchViewModel.MeetingCountdown(eventID: "e", title: "Standup", start: .now, color: .blue)
        notch.setMeetingCountdown(meeting)
        #expect(notch.liveActivity == .meeting(meeting))
        #expect(notch.bodySize.width == notch.notchSize.width + 2 * notch.wingWidth)
    }

    @Test func expandingOpensTabOfLiveActivity() {
        notch.setMusic(.init(trackID: "t", artworkURL: nil))
        notch.tapNotch()
        #expect(notch.selectedTab == .spotify)
        notch.clickedOutside()
        notch.setMeetingCountdown(.init(eventID: "e", title: "x", start: .now, color: .blue))
        notch.tapNotch()
        #expect(notch.selectedTab == .calendar)
    }

    @Test func stopCountdownHidesItAndReportsEvent() {
        var stopped: String?
        notch.onStopCountdown = { stopped = $0 }
        notch.setMeetingCountdown(.init(eventID: "e1", title: "x", start: .now, color: .blue))
        notch.stopCountdown()
        #expect(stopped == "e1")
        #expect(notch.meetingCountdown == nil)
    }

    @Test func restingOnCountdownArmsStopButton() async throws {
        notch.setMeetingCountdown(.init(eventID: "e1", title: "x", start: .now, color: .blue))
        notch.trailingWingHover(true)
        #expect(!notch.countdownStopArmed)
        try await Task.sleep(for: NotchViewModel.stopArmDelay + .milliseconds(300))
        #expect(notch.countdownStopArmed)
        notch.trailingWingHover(false)
        #expect(!notch.countdownStopArmed)
    }
}
