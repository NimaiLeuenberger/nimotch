import AppKit

/// Where the notch shape hangs on one display. On displays without a hardware notch
/// (external monitors) a pill of `fallbackWidth` × menu-bar height is used instead.
struct NotchGeometry: Equatable {
    static let fallbackWidth: CGFloat = 180
    static let minimumHeight: CGFloat = 24

    let screenFrame: CGRect
    let notchSize: CGSize
    let hasHardwareNotch: Bool

    /// Pure initializer (unit-tested): `safeAreaTop` > 0 plus both auxiliary areas means a real notch.
    init(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
         auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?) {
        self.screenFrame = screenFrame
        if safeAreaTop > 0, let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
            hasHardwareNotch = true
            notchSize = CGSize(width: screenFrame.width - left - right, height: safeAreaTop)
        } else {
            hasHardwareNotch = false
            let menuBar = screenFrame.maxY - visibleFrame.maxY
            notchSize = CGSize(width: Self.fallbackWidth, height: max(menuBar, Self.minimumHeight))
        }
    }

    init(screen: NSScreen) {
        self.init(screenFrame: screen.frame,
                  visibleFrame: screen.visibleFrame,
                  safeAreaTop: screen.safeAreaInsets.top,
                  auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
                  auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width)
    }

    /// Screen-space rect (bottom-left origin) of a shape of `size` hanging from the top-center.
    func rect(for size: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2,
               y: screenFrame.maxY - size.height,
               width: size.width,
               height: size.height)
    }
}
