import XCTest
import AppKit
@testable import CopyGlass

/// Exercises the pin-to-screen window lifecycle without needing screen recording permission.
final class PinWindowManagerTests: XCTestCase {
    func testPinAndUnpinLifecycle() throws {
        let image = TestImage.solid(.red, width: 60, height: 40)
        let controller = try XCTUnwrap(PinWindowManager.shared.pin(image: image, at: CGPoint(x: 400, y: 400)))
        XCTAssertEqual(PinWindowManager.shared.count, 1)
        XCTAssertNotNil(controller.window)
        XCTAssertEqual(controller.image.width, 60)
        XCTAssertEqual(controller.window?.level, .floating)
        XCTAssertEqual(
            controller.window?.sharingType,
            NSWindow.SharingType.none,
            "pinned windows must stay out of captures"
        )

        controller.setOpacity(0.5)
        XCTAssertEqual(controller.window?.alphaValue ?? 0, 0.5, accuracy: 0.001)

        let menu = controller.makeContextMenu()
        XCTAssertGreaterThanOrEqual(menu.items.count, 6, "the pinned window exposes a context menu")

        controller.close()
        XCTAssertEqual(PinWindowManager.shared.count, 0)

        PinWindowManager.shared.pin(image: image, at: nil)
        PinWindowManager.shared.pin(image: image, at: nil)
        XCTAssertEqual(PinWindowManager.shared.count, 2)
        PinWindowManager.shared.unpinAll()
        XCTAssertEqual(PinWindowManager.shared.count, 0)
    }
}
