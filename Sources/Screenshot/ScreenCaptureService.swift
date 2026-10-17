import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case displayNotFound
    case windowNotFound
    case emptySelection
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return L10n.t(.screenshotPermissionRequired, lang: .zhHans)
        case .displayNotFound:
            return "找不到显示器 / Display not found"
        case .windowNotFound:
            return "找不到窗口 / Window not found"
        case .emptySelection:
            return "选区为空 / Empty selection"
        case .captureFailed(let message):
            return message
        }
    }
}

/// Thin wrapper over ScreenCaptureKit used for every screenshot flavour (full screen, region,
/// window). Images are returned as CGImage at native (Retina) pixel resolution.
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    /// Enumerating shareable content is the slow part of a capture (tens to hundreds of ms on the
    /// first call). Caching it keeps the frame captured right after the hotkey fresh, which is what
    /// stops the frozen screen from visibly "jumping" back in time.
    private let contentLock = NSLock()
    private var cachedContent: SCShareableContent?
    private var cachedContentDate: Date?
    private let contentCacheLifetime: TimeInterval = 5

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateContentCache()
        }
    }

    /// Prepares the shareable content in the background so the next capture starts instantly.
    func warmUp() {
        guard Self.hasPermission else { return }
        Task.detached(priority: .utility) { [weak self] in
            _ = try? await self?.shareableContent()
        }
    }

    func invalidateContentCache() {
        contentLock.lock()
        cachedContent = nil
        cachedContentDate = nil
        contentLock.unlock()
    }

    /// Shared options for still captures: no cursor and an explicit SDR range, because an HDR
    /// capture would make an XDR display switch modes (a visible flash).
    private static func makeConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.captureResolution = .best
        if #available(macOS 15.0, *) {
            configuration.captureDynamicRange = .SDR
        }
        return configuration
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static func openScreenRecordingSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for string in candidates {
            if let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        contentLock.lock()
        let cached = cachedContent
        let age = cachedContentDate.map { Date().timeIntervalSince($0) } ?? .infinity
        contentLock.unlock()
        if let cached, age < contentCacheLifetime {
            return cached
        }

        guard Self.hasPermission else { throw ScreenCaptureError.permissionDenied }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            contentLock.lock()
            cachedContent = content
            cachedContentDate = Date()
            contentLock.unlock()
            return content
        } catch {
            throw ScreenCaptureError.captureFailed(error.localizedDescription)
        }
    }

    func backingScale(for displayID: CGDirectDisplayID) -> CGFloat {
        NSScreen.screen(withDisplayID: displayID)?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    /// Captures an entire display at native pixel resolution.
    func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> CGImage {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = backingScale(for: displayID)
        let configuration = Self.makeConfiguration()
        configuration.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
        configuration.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw ScreenCaptureError.captureFailed(error.localizedDescription)
        }
    }

    /// Captures every attached display, keyed by display id.
    func captureAllDisplays() async throws -> [CGDirectDisplayID: CGImage] {
        let content = try await shareableContent()
        var result: [CGDirectDisplayID: CGImage] = [:]
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = backingScale(for: display.displayID)
            let configuration = Self.makeConfiguration()
            configuration.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
            configuration.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
            do {
                result[display.displayID] = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            } catch {
                throw ScreenCaptureError.captureFailed(error.localizedDescription)
            }
        }
        return result
    }

    /// Captures a rectangle expressed in Cocoa global coordinates. Selections spanning several
    /// displays are captured per display and composited into a single image.
    func captureRegion(_ cocoaRect: CGRect) async throws -> CGImage {
        let rect = cocoaRect.standardized.integral
        guard rect.width >= 1, rect.height >= 1 else { throw ScreenCaptureError.emptySelection }
        guard let involved = Self.displays(intersecting: rect) else { throw ScreenCaptureError.emptySelection }

        var images: [CGDirectDisplayID: CGImage] = [:]
        for part in involved {
            images[part.displayID] = try await captureDisplay(part.displayID)
        }
        guard let composited = Self.compositeRegion(rect, images: images, scaleFor: { [weak self] id in
            self?.backingScale(for: id) ?? 2
        }) else {
            throw ScreenCaptureError.emptySelection
        }
        return composited
    }

    /// Displays whose frame intersects the given Cocoa-global rectangle, with the intersection.
    static func displays(intersecting rect: CGRect) -> [(rect: CGRect, displayID: CGDirectDisplayID, screenFrame: CGRect)]? {
        var parts: [(rect: CGRect, displayID: CGDirectDisplayID, screenFrame: CGRect)] = []
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(rect)
            guard !intersection.isNull, intersection.width >= 1, intersection.height >= 1 else { continue }
            guard let id = screen.displayID else { continue }
            parts.append((intersection, id, screen.frame))
        }
        return parts.isEmpty ? nil : parts
    }

    /// Crops a Cocoa-global rectangle out of already captured per-display images. Used by the
    /// frozen-screen overlay so annotations never need a second capture.
    static func compositeRegion(
        _ cocoaRect: CGRect,
        images: [CGDirectDisplayID: CGImage],
        scaleFor: (CGDirectDisplayID) -> CGFloat
    ) -> CGImage? {
        let rect = cocoaRect.standardized.integral
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        guard let parts = displays(intersecting: rect) else { return nil }

        if parts.count == 1, let only = parts.first, let image = images[only.displayID] {
            let scale = scaleFor(only.displayID)
            // Convert the Cocoa intersection into the display image top-left pixel space.
            let pixelRect = CGRect(
                x: (only.rect.minX - only.screenFrame.minX) * scale,
                y: (only.screenFrame.maxY - only.rect.maxY) * scale,
                width: only.rect.width * scale,
                height: only.rect.height * scale
            )
            return ImageUtils.crop(image, topLeftRect: pixelRect)
        }

        let captureScale = parts.map { scaleFor($0.displayID) }.max() ?? 2
        let outputWidth = Int((rect.width * captureScale).rounded())
        let outputHeight = Int((rect.height * captureScale).rounded())
        guard let context = ImageUtils.makeContext(width: outputWidth, height: outputHeight) else { return nil }
        context.interpolationQuality = .high
        for part in parts {
            guard let image = images[part.displayID] else { continue }
            let topOffset = (rect.maxY - part.rect.maxY) * captureScale
            let height = part.rect.height * captureScale
            let drawRect = CGRect(
                x: (part.rect.minX - rect.minX) * captureScale,
                y: CGFloat(outputHeight) - topOffset - height,
                width: part.rect.width * captureScale,
                height: height
            )
            context.draw(image, in: drawRect)
        }
        return context.makeImage()
    }

    /// Captures a single window by its CoreGraphics window id.
    func captureWindow(_ windowID: CGWindowID) async throws -> CGImage {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cocoaFrame = ScreenGeometry.cocoaRect(fromQuartz: window.frame)
        let scale = ScreenGeometry.screen(bestMatching: cocoaFrame)?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let configuration = Self.makeConfiguration()
        configuration.ignoreShadowsSingleWindow = false
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw ScreenCaptureError.captureFailed(error.localizedDescription)
        }
    }
}
