import AppKit
import SwiftUI

/// Owns the notch panel: positions it on the built-in display, routes mouse
/// tracking into the view model and lets clicks pass through outside the shape.
@MainActor
final class NotchWindowController {
    private let viewModel: NotchViewModel
    private let rootView: AnyView
    private var panel: NotchPanel?
    private var eventMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?

    /// - Parameter rootView: the notch content, with all module services already injected
    ///   into the environment (see `AppDelegate.makeNotchRootView`).
    init(viewModel: NotchViewModel, rootView: some View) {
        self.viewModel = viewModel
        self.rootView = AnyView(rootView)
        viewModel.layoutDidChange = { [weak self] in
            self?.updateHitTesting()
            self?.relinquishKeyFocusIfCollapsed()
        }
        viewModel.requestKeyFocus = { [weak self] in self?.panel?.makeKey() }
        rebuild()
        installEventMonitors()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    // MARK: Window placement
    private func rebuild() {
        guard let screen = NotchGeometry.builtInScreen(),
              let geometry = NotchGeometry(screen: screen)
        else {
            panel?.orderOut(nil)
            viewModel.geometry = nil
            return
        }
        viewModel.geometry = geometry

        let canvas = NotchViewModel.canvasSize
        let frame = CGRect(x: geometry.screenFrame.midX - canvas.width / 2,
                           y: geometry.screenFrame.maxY - canvas.height,
                           width: canvas.width,
                           height: canvas.height)
        let panel = panel ?? makePanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        updateHitTesting()
    }

    private func makePanel(frame: CGRect) -> NotchPanel {
        let panel = NotchPanel(contentRect: frame)
        let hosting = FirstMouseHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    /// Hands the keyboard back to the frontmost app once the panel collapses.
    private func relinquishKeyFocusIfCollapsed() {
        guard let panel, panel.isKeyWindow, viewModel.mode != .expanded else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: Mouse tracking
    private func installEventMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHitTesting() }
        }) { eventMonitors.append(global) }

        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateHitTesting() }
            return event
        }) { eventMonitors.append(local) }

        // Global monitors only see clicks in other apps' windows, i.e. outside nimotch.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.viewModel.clickedOutside() }
        }) { eventMonitors.append(outside) }
    }

    /// Makes the panel clickable only while the mouse is over the visible shape.
    private func updateHitTesting() {
        guard let panel, let geometry = viewModel.geometry else { return }
        var rect = geometry.rect(for: viewModel.shapeSize)
        rect = rect.insetBy(dx: viewModel.mode == .collapsed ? -4 : -8, dy: 0)
        rect.origin.y -= viewModel.mode == .collapsed ? 2 : 8
        rect.size.height += viewModel.mode == .collapsed ? 6 : 12   // also covers the very top pixel row

        let mouse = NSEvent.mouseLocation
        let inside = rect.contains(mouse)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        viewModel.mouseMoved(inside: inside)

        // Trailing wing (right of the hardware notch), for the countdown's stop button.
        let shape = geometry.rect(for: viewModel.shapeSize)
        var wing = CGRect(x: shape.maxX - viewModel.topRadius - viewModel.wingWidth, y: shape.minY,
                          width: viewModel.wingWidth + viewModel.topRadius, height: shape.height)
        wing.size.height += 4
        viewModel.trailingWingHover(viewModel.mode == .collapsed && viewModel.hasWings && wing.contains(mouse))
    }
}
