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
    /// System-owned windows that are never a document to capture: the menu bar, Dock, Notification
    /// Centre, Control Centre, Stage Manager, Spotlight, the lock screen and Apple's screenshot UI.
    /// Bundle identifiers are matched first because owner names are localised; the names below are
    /// the fallback for processes that have no running application (the window server itself).
    static let excludedOwnerBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.WindowManager",
        "com.apple.systemuiserver",
        "com.apple.loginwindow",
        "com.apple.Spotlight",
        "com.apple.screencaptureui",
        "com.apple.ScreenSaver.Engine"
    ]

    static let excludedOwnerNames: Set<String> = [
        "Window Server", "WindowManager", "Dock", "Notification Center", "Control Center",
        "程序坞", "通知中心", "控制中心"
    ]

    /// Smallest window edge that can still be aimed at with the mouse.
    static let minimumSide: CGFloat = 24

    static func candidates() -> [CapturableWindow] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var bundleIdentifiers: [pid_t: String] = [:]
        var result: [CapturableWindow] = []

        func bundleIdentifier(for pid: pid_t) -> String? {
            if let cached = bundleIdentifiers[pid] {
                return cached.isEmpty ? nil : cached
            }
            let identifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            bundleIdentifiers[pid] = identifier
            return identifier.isEmpty ? nil : identifier
        }

        for info in infoList {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let quartzRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let pid = pid_t((info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0)
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            let cocoaFrame = ScreenGeometry.cocoaRect(fromQuartz: quartzRect)
            guard isCapturable(
                layer: layer,
                alpha: alpha,
                cocoaFrame: cocoaFrame,
                ownerPID: pid,
                ownerName: ownerName,
                ownerBundleIdentifier: bundleIdentifier(for: pid),
                ownPID: ownPID
            ) else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            result.append(CapturableWindow(
                id: CGWindowID(windowID),
                ownerPID: pid,
                cocoaFrame: cocoaFrame,
                title: title,
                ownerName: ownerName,
                layer: layer
            ))
        }
        return result
    }

    /// Whether an on-screen window can be picked as a capture target.
    ///
    /// Windows are pickable at any non-negative layer: normal windows (0) plus the floating panels,
    /// palettes, dialogs and always-on-top popups above them — `NSWindow.Level.floating` is 3,
    /// `modalPanel` is 8, and apps such as music mini players or translation bubbles sit above the
    /// menu bar (24) and status bar (25). Negative layers are the desktop wallpaper and WidgetKit
    /// widgets, which are never a document. The old check required layer 0 exactly, which silently
    /// hid every floating window from window-pick; the owner exclusions below keep system chrome out
    /// instead of relying on the layer number.
    static func isCapturable(
        layer: Int,
        alpha: Double,
        cocoaFrame: CGRect,
        ownerPID: pid_t,
        ownerName: String,
        ownerBundleIdentifier: String?,
        ownPID: pid_t
    ) -> Bool {
        guard layer >= 0, alpha > 0.01 else { return false }
        guard cocoaFrame.width >= minimumSide, cocoaFrame.height >= minimumSide else { return false }
        guard ownerPID != ownPID else { return false }
        if let ownerBundleIdentifier, excludedOwnerBundleIdentifiers.contains(ownerBundleIdentifier) {
            return false
        }
        return !excludedOwnerNames.contains(ownerName)
    }

    /// Front-to-back hit test; CGWindowListCopyWindowInfo returns windows in front-to-back order.
    static func window(at cocoaPoint: CGPoint, in candidates: [CapturableWindow]) -> CapturableWindow? {
        candidates.first { $0.cocoaFrame.contains(cocoaPoint) }
    }
}
