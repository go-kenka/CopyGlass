import XCTest
import AppKit
@testable import CopyGlass

/// Covers the presentation contract of the frozen-desktop overlay.
///
/// The overlay windows are mapped invisibly (and click-through) while the capture runs, the frozen
/// frame is drawn into them while they are still transparent, and only then are they revealed and
/// activated — in that order. Getting this wrong leaves the live desktop visible for a few frames
/// while focus changes, which is the "window flashes" bug when a capture is triggered.
final class OverlayPresentationTests: XCTestCase {
    private func makeOverlayWindow() -> SelectionOverlayWindow {
        SelectionOverlayWindow(
            contentRect: CGRect(x: 0, y: 0, width: 160, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }

    func testPrewarmedOverlayWindowIsInvisibleAndClickThrough() {
        let window = makeOverlayWindow()
        defer { window.orderOut(nil); window.close() }
        RegionSelectionController.configureOverlayWindowForPrewarm(window)

        XCTAssertEqual(window.alphaValue, 0, "a pre-warmed overlay must not show anything yet")
        XCTAssertTrue(window.ignoresMouseEvents, "a pre-warmed overlay must not swallow events")
        XCTAssertEqual(window.level, .screenSaver, "the frozen screen has to cover the menu bar")
        XCTAssertFalse(window.isOpaque)
        XCTAssertFalse(window.hasShadow)
        XCTAssertEqual(window.sharingType, .none, "the overlay must stay out of further captures")
        XCTAssertEqual(
            window.animationBehavior,
            .none,
            "dismissing the frozen overlay must be a hard cut, a system fade-out reads as a flash"
        )
        XCTAssertTrue(window.canBecomeKey, "the overlay handles keyboard shortcuts")
        XCTAssertFalse(window.canBecomeMain, "the overlay must not join window/Space management")
    }

    func testRevealMakesTheOverlayVisibleAndInteractiveInOneStep() {
        let window = makeOverlayWindow()
        defer { window.orderOut(nil); window.close() }
        RegionSelectionController.configureOverlayWindowForPrewarm(window)
        window.contentView = NSView(frame: CGRect(origin: .zero, size: window.frame.size))

        RegionSelectionController.revealOverlayWindows([window])

        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertFalse(window.ignoresMouseEvents)
    }

    func testOverlayViewAcceptsTheFrozenFrameAfterBeingPrewarmed() throws {
        let screen = try XCTUnwrap(NSScreen.main, "needs a window server session")
        let view = SelectionOverlayView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            controller: RegionSelectionController.shared,
            screen: screen,
            image: nil
        )
        XCTAssertNil(view.image, "the pre-warmed overlay starts without a frame")

        let frozen = TestImage.solid(.white, width: 4, height: 4)
        view.update(image: frozen)

        XCTAssertEqual(view.image?.width, 4)
        XCTAssertEqual(view.image?.height, 4)
    }
}
