import XCTest
import AppKit
@testable import CopyGlass

/// Builds the real SwiftUI editor window so the view tree is exercised by the test run.
final class ScreenshotEditorTests: XCTestCase {
    func testEditorWindowCanBePresentedAndClosed() throws {
        let image = TestImage.solid(.white, width: 320, height: 240)
        let controller = ScreenshotEditorManager.shared.present(image: image, runOCR: false)
        XCTAssertNotNil(controller.window)
        XCTAssertEqual(ScreenshotEditorManager.shared.windowCount, 1)
        XCTAssertEqual(controller.model.imagePixelSize.width, 320)

        // The model supports the whole editing surface the editor exposes.
        let shape = AnnotationShape(
            tool: .arrow,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100)],
            color: AnnotationColor.palette[3],
            lineWidth: 5
        )
        controller.model.commit(shape)
        XCTAssertTrue(controller.model.hasAnnotations)
        XCTAssertEqual(controller.model.flattenedImage().width, 320)

        controller.window?.orderOut(nil)
        controller.close()
        XCTAssertEqual(ScreenshotEditorManager.shared.windowCount, 0)
    }
}
