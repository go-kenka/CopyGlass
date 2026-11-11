import Foundation
import AppKit
import CoreGraphics

/// Entry points for every screenshot flavour, wired to the menu bar and global hotkeys. All flows
/// run through the frozen overlay: window-first selection, then Feishu-style in-place editing.
final class ScreenshotController {
    static let shared = ScreenshotController()

    private init() {}

    func captureRegion() {
        guard ensurePermission(), !ScrollingCaptureController.shared.isRunning else { return }
        RegionSelectionController.shared.begin(
            mode: .region,
            purpose: .edit,
            onError: { [weak self] error in self?.presentError(error) },
            onScrollingCapture: { [weak self] region in self?.startScrolling(region: region) }
        )
    }

    func captureWindow() {
        guard ensurePermission(), !ScrollingCaptureController.shared.isRunning else { return }
        RegionSelectionController.shared.begin(
            mode: .window,
            purpose: .edit,
            onError: { [weak self] error in self?.presentError(error) },
            onScrollingCapture: { [weak self] region in self?.startScrolling(region: region) }
        )
    }

    func captureFullScreen() {
        guard ensurePermission(), !ScrollingCaptureController.shared.isRunning else { return }
        let point = NSEvent.mouseLocation
        guard let screen = ScreenGeometry.screen(containing: point) ?? NSScreen.main else { return }
        RegionSelectionController.shared.begin(
            mode: .region,
            purpose: .edit,
            preselect: screen.frame,
            onError: { [weak self] error in self?.presentError(error) },
            onScrollingCapture: { [weak self] region in self?.startScrolling(region: region) }
        )
    }

    func captureScrolling() {
        guard ensurePermission(), !ScrollingCaptureController.shared.isRunning else { return }
        RegionSelectionController.shared.begin(
            mode: .region,
            purpose: .scroll,
            onError: { [weak self] error in self?.presentError(error) },
            onScrollingCapture: { [weak self] region in self?.startScrolling(region: region) }
        )
    }

    /// Runs the manual scrolling capture for a confirmed region.
    ///
    /// A stitched long image is not the frozen screen, so it opens in the editor window: the user can
    /// annotate, extract text, copy, save or pin it, but it can no longer be re-captured or resized.
    func startScrolling(region: CGRect) {
        ScrollingCaptureController.shared.start(region: region) { [weak self] image in
            guard let image else { return }
            // Reuse the ordinary capture editor: the stitched image takes the place of the capture
            // frame and is edited in place with the same overlay, toolbar and shortcuts.
            RegionSelectionController.shared.begin(
                mode: .region,
                purpose: .edit,
                longImage: image,
                screenHint: ScreenGeometry.screen(bestMatching: region),
                onError: { [weak self] error in self?.presentError(error) }
            )
        }
    }

    func extractText() {
        guard ensurePermission(), !ScrollingCaptureController.shared.isRunning else { return }
        RegionSelectionController.shared.begin(
            mode: .region,
            purpose: .extractText,
            onError: { [weak self] error in self?.presentError(error) }
        )
    }

    func ensurePermission() -> Bool {
        if ScreenCaptureService.hasPermission { return true }
        let lang = AppLanguage.current
        let alert = NSAlert()
        alert.messageText = L10n.t(.screenRecordingPermissionTitle, lang: lang)
        alert.informativeText = L10n.t(.screenRecordingPermissionMessage, lang: lang)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.t(.openSystemSettings, lang: lang))
        alert.addButton(withTitle: L10n.t(.cancel, lang: lang))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = ScreenCaptureService.requestPermission()
            ScreenCaptureService.openScreenRecordingSettings()
        }
        return false
    }

    func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.t(.screenshotFailed, lang: AppLanguage.current)
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
