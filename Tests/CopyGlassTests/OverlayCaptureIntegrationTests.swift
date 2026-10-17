import XCTest
import AppKit
@testable import CopyGlass

/// End-to-end smoke test for the frozen overlay: the windows are laid down invisibly before the
/// capture, revealed with the frozen frame when it arrives, and torn down cleanly.
///
/// It needs a real display and screen recording permission, so it is skipped unless
/// `COPYGLASS_OVERLAY_INTEGRATION=1` is set. Run it on a GUI machine with:
///
///     COPYGLASS_OVERLAY_INTEGRATION=1 swift test --filter OverlayCaptureIntegrationTests
final class OverlayCaptureIntegrationTests: XCTestCase {
    private var overlayWindows: [SelectionOverlayWindow] {
        NSApplication.shared.windows.compactMap { $0 as? SelectionOverlayWindow }.filter { $0.isVisible }
    }

    private func spin(until deadline: Date, condition: () -> Bool) -> Bool {
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func skipUnlessIntegrationEnabled() throws {
        // The app registers these at launch; tests have to do it themselves so the editor (rather
        // than the copy-straight-to-clipboard path) runs.
        ScreenshotDefaults.register()
        guard ProcessInfo.processInfo.environment["COPYGLASS_OVERLAY_INTEGRATION"] == "1" else {
            throw XCTSkip("set COPYGLASS_OVERLAY_INTEGRATION=1 to run this display/SCK integration test")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("screen recording permission is required")
        }
    }

    func testCapturePresentsFrozenOverlayAndTearsDown() throws {
        try skipUnlessIntegrationEnabled()

        let controller = RegionSelectionController.shared
        XCTAssertFalse(controller.isActive)
        var captureError: Error?
        controller.begin(mode: .region, purpose: .edit, onError: { captureError = $0 })
        defer {
            if controller.isActive { controller.cancel() }
        }

        // The windows are already mapped — transparent and click-through — while the capture runs.
        let screens = NSScreen.screens
        XCTAssertTrue(
            spin(until: Date().addingTimeInterval(0.5)) { self.overlayWindows.count == screens.count },
            "an overlay window per display must be pre-warmed before the capture finishes"
        )
        for window in overlayWindows {
            XCTAssertEqual(window.alphaValue, 0, "pre-warmed overlays stay invisible")
            XCTAssertTrue(window.ignoresMouseEvents, "pre-warmed overlays stay click-through")
        }

        // When the frozen frames arrive the overlays are revealed with their content in place.
        XCTAssertTrue(
            spin(until: Date().addingTimeInterval(6)) {
                captureError != nil || self.overlayWindows.allSatisfy { $0.alphaValue == 1 }
            },
            "the overlay must be revealed once the capture lands"
        )
        if let captureError {
            throw XCTSkip("screen capture is unavailable here: \(captureError)")
        }
        XCTAssertEqual(overlayWindows.count, screens.count)
        for window in overlayWindows {
            XCTAssertEqual(window.alphaValue, 1)
            XCTAssertFalse(window.ignoresMouseEvents)
            let view = try XCTUnwrap(window.contentView as? SelectionOverlayView)
            XCTAssertNotNil(view.image, "the revealed overlay must already contain the frozen frame")
        }

        // Cancelling restores the previous app and closes the overlays.
        controller.cancel()
        XCTAssertTrue(
            spin(until: Date().addingTimeInterval(1.5)) { !controller.isActive && self.overlayWindows.isEmpty },
            "cancelling must close the overlay windows"
        )
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(overlayWindows.isEmpty)
    }

    /// Copying recognized text finishes the capture instead of leaving the overlay up with the text
    /// panel open.
    func testCopyingRecognizedTextClosesTheCapture() throws {
        try skipUnlessIntegrationEnabled()

        let controller = RegionSelectionController.shared
        XCTAssertFalse(controller.isActive)
        var captureError: Error?
        controller.begin(mode: .region, purpose: .edit, onError: { captureError = $0 })
        defer {
            if controller.isActive { controller.cancel() }
        }

        XCTAssertTrue(
            spin(until: Date().addingTimeInterval(6)) {
                captureError != nil || (!self.overlayWindows.isEmpty && self.overlayWindows.allSatisfy { $0.alphaValue == 1 })
            },
            "the overlay must be revealed once the capture lands"
        )
        if let captureError {
            throw XCTSkip("screen capture is unavailable here: \(captureError)")
        }

        // Draw a selection and open the text panel first: copying from the panel must finish the
        // capture from the editing phase, not leave it up.
        controller.handleMouseDown(at: CGPoint(x: 400, y: 400))
        controller.handleMouseDragged(to: CGPoint(x: 700, y: 600))
        controller.handleMouseUp(at: CGPoint(x: 700, y: 600))
        XCTAssertEqual(controller.phase, .editing)
        controller.session?.panel = .ocr

        let pasteboard = NSPasteboard.general
        let savedText = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let savedText { pasteboard.setString(savedText, forType: .string) }
        }

        controller.performCopyText("CopyGlass OCR")
        XCTAssertTrue(
            spin(until: Date().addingTimeInterval(1.5)) { !controller.isActive && self.overlayWindows.isEmpty },
            "copying recognized text must close the overlay"
        )
        XCTAssertNil(controller.session, "the editing session must be released with the overlay")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "CopyGlass OCR")
    }

    /// The capture frame can still be resized and moved while annotating; annotations keep their
    /// position on the frozen screen.
    func testCaptureFrameCanBeResizedAndMovedWhileEditing() throws {
        try skipUnlessIntegrationEnabled()

        let controller = RegionSelectionController.shared
        XCTAssertFalse(controller.isActive)
        var captureError: Error?
        controller.begin(mode: .region, purpose: .edit, onError: { captureError = $0 })
        defer {
            if controller.isActive { controller.cancel() }
        }
        XCTAssertTrue(
            spin(until: Date().addingTimeInterval(6)) {
                captureError != nil || (!self.overlayWindows.isEmpty && self.overlayWindows.allSatisfy { $0.alphaValue == 1 })
            },
            "the overlay must be revealed once the capture lands"
        )
        if let captureError {
            throw XCTSkip("screen capture is unavailable here: \(captureError)")
        }

        // Draw a selection to enter the in-place editing phase.
        controller.handleMouseDown(at: CGPoint(x: 400, y: 400))
        controller.handleMouseDragged(to: CGPoint(x: 700, y: 600))
        controller.handleMouseUp(at: CGPoint(x: 700, y: 600))
        XCTAssertEqual(controller.phase, .editing)
        let session = try XCTUnwrap(controller.session)
        let startFrame = controller.selection
        XCTAssertEqual(startFrame.width, 300, accuracy: 2)
        XCTAssertEqual(startFrame.height, 200, accuracy: 2)

        // A rectangle annotation, whose position on screen has to survive frame adjustments.
        let shape = AnnotationShape(
            tool: .rectangle,
            points: [CGPoint(x: 40, y: 40), CGPoint(x: 120, y: 90)],
            color: AnnotationColor.palette[0],
            lineWidth: 4
        )
        session.commit(shape)
        let startImageWidth = session.image.width
        let screenPointBefore = screenPoint(for: shape.points[0], selection: controller.selection, image: session.image)

        // Resize by dragging the left edge 60 points out. The frame origin moves too, so this only
        // passes if the annotations are remapped rather than left in image coordinates.
        let leftEdge = CGPoint(x: startFrame.minX, y: startFrame.midY)
        controller.beginSelectionAdjustment(handle: .left, at: leftEdge)
        controller.updateSelectionAdjustment(to: CGPoint(x: leftEdge.x - 60, y: leftEdge.y))
        controller.endSelectionAdjustment()

        XCTAssertLessThan(controller.selection.minX, startFrame.minX, "the left edge must have moved out")
        XCTAssertGreaterThan(controller.selection.width, startFrame.width + 40)
        XCTAssertGreaterThan(session.image.width, startImageWidth + 50, "the crop must be rebuilt for the wider frame")
        let screenPointAfterResize = screenPoint(for: session.shapes[0].points[0], selection: controller.selection, image: session.image)
        XCTAssertEqual(screenPointAfterResize.x, screenPointBefore.x, accuracy: 1.5)
        XCTAssertEqual(screenPointAfterResize.y, screenPointBefore.y, accuracy: 1.5)

        // Move the whole frame and verify the annotation follows the screen.
        let resizedFrame = controller.selection
        let centre = CGPoint(x: resizedFrame.midX, y: resizedFrame.midY)
        controller.beginSelectionAdjustment(handle: nil, at: centre)
        controller.updateSelectionAdjustment(to: CGPoint(x: centre.x - 40, y: centre.y - 30))
        controller.endSelectionAdjustment()

        XCTAssertEqual(controller.selection.width, resizedFrame.width, accuracy: 1)
        XCTAssertLessThan(controller.selection.minX, resizedFrame.minX, "the frame must have moved left")
        let screenPointAfterMove = screenPoint(for: session.shapes[0].points[0], selection: controller.selection, image: session.image)
        XCTAssertEqual(screenPointAfterMove.x, screenPointBefore.x, accuracy: 1.5)
        XCTAssertEqual(screenPointAfterMove.y, screenPointBefore.y, accuracy: 1.5)
    }

    /// Where an image-space point of the current crop lands in Cocoa global coordinates.
    private func screenPoint(for imagePoint: CGPoint, selection: CGRect, image: CGImage) -> CGPoint {
        let scale = selection.width / CGFloat(image.width)
        return CGPoint(
            x: selection.minX + imagePoint.x * scale,
            y: selection.minY + (CGFloat(image.height) - imagePoint.y) * scale
        )
    }
}
