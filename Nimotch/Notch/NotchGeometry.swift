import AppKit

/// Position and size of the hardware notch on the built-in display.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchSize: CGSize

    init?(screen: NSScreen) {
        let height = screen.safeAreaInsets.top
        guard height > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }
        screenFrame = screen.frame
        notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: height)
    }

    /// The built-in (laptop) display, or nil when the lid is closed.
    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let id = screen.deviceDescription[key] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
    }

    /// Screen-space rect (bottom-left origin) of a shape of `size` hanging from the top-center.
    func rect(for size: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2,
               y: screenFrame.maxY - size.height,
               width: size.width,
               height: size.height)
    }
}
