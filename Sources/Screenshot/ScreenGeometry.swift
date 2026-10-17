import Foundation
import AppKit
import CoreGraphics

extension NSScreen {
    /// The CoreGraphics display identifier backing this screen.
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == id }
    }
}

/// Conversions between Cocoa global coordinates (bottom-left origin, used by NSEvent and NSScreen)
/// and Quartz display coordinates (top-left origin, used by CoreGraphics window listings and
/// SCWindow).
enum ScreenGeometry {
    /// Height of the primary display, the reference used to flip Y between the two spaces.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? CGDisplayBounds(CGMainDisplayID()).height
    }

    static func cocoaRect(fromQuartz rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func quartzRect(fromCocoa rect: CGRect) -> CGRect {
        cocoaRect(fromQuartz: rect)
    }

    static func cocoaPoint(fromQuartz point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func quartzPoint(fromCocoa point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Union of every attached screen in Cocoa global coordinates.
    static var screensUnion: CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// Screen with the largest intersection with rect.
    static func screen(bestMatching rect: CGRect) -> NSScreen? {
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let inter = screen.frame.intersection(rect)
            guard !inter.isNull else { continue }
            let area = inter.width * inter.height
            if area > 0, best == nil || area > best!.area {
                best = (screen, area)
            }
        }
        return best?.screen ?? screen(containing: rect.center)
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    init(point a: CGPoint, point b: CGPoint) {
        self.init(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }
}
