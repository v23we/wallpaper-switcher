import AppKit
import CoreGraphics

struct BuiltInDisplayResolver {
    func resolveTargetScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            guard let displayID = displayID(for: screen) else {
                continue
            }

            if CGDisplayIsBuiltin(displayID) != 0 {
                return screen
            }
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
