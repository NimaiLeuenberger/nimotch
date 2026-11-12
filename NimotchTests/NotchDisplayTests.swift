import Foundation
import Testing
@testable import nimotch

@Suite("Displays: geometry and per-display settings")
struct NotchDisplayTests {
    let macBook = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    @Test func hardwareNotchUsesAuxiliaryAreas() {
        let g = NotchGeometry(screenFrame: macBook, visibleFrame: macBook, safeAreaTop: 32,
                              auxiliaryLeftWidth: 771, auxiliaryRightWidth: 772)
        #expect(g.hasHardwareNotch)
        #expect(g.notchSize == CGSize(width: 185, height: 32))
    }

    @Test func externalDisplayGetsMenuBarHighPill() {
        let frame = CGRect(x: -837, y: 1117, width: 3440, height: 1440)
        var visible = frame
        visible.size.height -= 25
        let g = NotchGeometry(screenFrame: frame, visibleFrame: visible, safeAreaTop: 0,
                              auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil)
        #expect(!g.hasHardwareNotch)
        #expect(g.notchSize == CGSize(width: NotchGeometry.fallbackWidth, height: 25))
        #expect(g.rect(for: g.notchSize).midX == frame.midX)
    }

    @Test func hiddenMenuBarStillGetsMinimumHeight() {
        let g = NotchGeometry(screenFrame: macBook, visibleFrame: macBook, safeAreaTop: 0,
                              auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil)
        #expect(g.notchSize.height == NotchGeometry.minimumHeight)
    }

    @Test func builtInOnByDefaultExternalOff() {
        let builtIn = DisplayInfo(id: DisplayInfo.builtInKey, name: "Built-in", isBuiltIn: true, hasNotch: true)
        let dell = DisplayInfo(id: "display-1-2-3", name: "DELL", isBuiltIn: false, hasNotch: false)
        #expect(NotchDisplays.isEnabled(builtIn, overrides: [:]))
        #expect(!NotchDisplays.isEnabled(dell, overrides: [:]))
        #expect(NotchDisplays.isEnabled(dell, overrides: ["display-1-2-3": true]))
        #expect(!NotchDisplays.isEnabled(builtIn, overrides: ["builtin": false]))
    }

    @Test func displayKeysAreStableAndUnique() {
        #expect(DisplayInfo.key(isBuiltIn: true, vendor: 1, model: 2, serial: 3) == "builtin")
        #expect(DisplayInfo.key(isBuiltIn: false, vendor: 1, model: 2, serial: 3) == "display-1-2-3")
        #expect(NotchDisplays.unique("display-1-2-0", existing: []) == "display-1-2-0")
        #expect(NotchDisplays.unique("display-1-2-0", existing: ["display-1-2-0"]) == "display-1-2-0#2")
        #expect(NotchDisplays.unique("d", existing: ["d", "d#2"]) == "d#3")
    }

    @Test func builtInListedFirst() {
        let sorted = NotchDisplays.sorted([
            DisplayInfo(id: "b", name: "B", isBuiltIn: false, hasNotch: false),
            DisplayInfo(id: "builtin", name: "Z Built-in", isBuiltIn: true, hasNotch: true),
            DisplayInfo(id: "a", name: "A", isBuiltIn: false, hasNotch: false),
        ])
        #expect(sorted.map(\.id) == ["builtin", "a", "b"])
    }
}

@MainActor
@Suite("Notch hub: broadcast to every display")
struct NotchHubTests {
    let hub = NotchHub()

    @Test func broadcastsToAllNotches() {
        let a = hub.makeNotch(), b = hub.makeNotch()
        hub.setNotches([a, b])
        hub.setMusic(.init(trackID: "t", artworkURL: nil))
        hub.showPeek(.init(icon: "bell", title: "Hi"))
        #expect(a.music?.trackID == "t" && b.music?.trackID == "t")
        #expect(a.mode == .peek && b.mode == .peek)
    }

    @Test func newNotchStartsWithCurrentState() {
        let countdown = NotchViewModel.MeetingCountdown(eventID: "e", title: "x", start: .now, color: .blue)
        hub.setMeetingCountdown(countdown)
        hub.setDemoWings(true)
        let late = hub.makeNotch()
        #expect(late.meetingCountdown == countdown)
        #expect(late.demoWings)
    }

    @Test func stoppingCountdownOnOneDisplayClearsAll() {
        var stopped: String?
        hub.onStopCountdown = { stopped = $0 }
        let a = hub.makeNotch(), b = hub.makeNotch()
        hub.setNotches([a, b])
        hub.setMeetingCountdown(.init(eventID: "e1", title: "x", start: .now, color: .blue))
        a.stopCountdown()
        #expect(stopped == "e1")
        #expect(a.meetingCountdown == nil && b.meetingCountdown == nil)
    }

    @Test func expandedStateAndMenuToggleUsePrimary() {
        let a = hub.makeNotch(), b = hub.makeNotch()
        hub.setNotches([a, b])
        #expect(!hub.isAnyExpanded)
        b.tapNotch()
        #expect(hub.isAnyExpanded)
        hub.toggleFromMenu()
        #expect(a.mode == .expanded)
    }
}
