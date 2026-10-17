import Foundation
import AppKit
import CoreGraphics

/// A window that can be picked for window-capture, described in Cocoa global coordinates.
struct CapturableWindow: Identifiable, Equatable {
    let id: CGWindowID
    let ownerPID: pid_t
    let cocoaFrame: CGRect
    let title: String
    let ownerName: String
    let layer: Int
}

/// Enumerates on-screen windows so a single click during region selection can pick a window.
enum WindowHitTester {
    static func candidates() -> [CapturableWindow] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [CapturableWindow] = []

        for info in infoList {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            guard let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let quartzRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            guard quartzRect.width >= 24, quartzRect.height >= 24 else { continue }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0.01 { continue }
            let pid = pid_t((info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0)
            if pid == ownPID { continue }
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            if ownerName == "Window Server" || ownerName == "Dock" || ownerName == "WindowManager" { continue }
            let title = info[kCGWindowName as String] as? String ?? ""
            result.append(CapturableWindow(
                id: CGWindowID(windowID),
                ownerPID: pid,
                cocoaFrame: ScreenGeometry.cocoaRect(fromQuartz: quartzRect),
                title: title,
                ownerName: ownerName,
                layer: layer
            ))
        }
        return result
    }

    /// Front-to-back hit test; CGWindowListCopyWindowInfo returns windows in front-to-back order.
    static func window(at cocoaPoint: CGPoint, in candidates: [CapturableWindow]) -> CapturableWindow? {
        candidates.first { $0.cocoaFrame.contains(cocoaPoint) }
    }
}
