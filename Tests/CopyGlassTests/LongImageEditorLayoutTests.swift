import XCTest
import CoreGraphics
import AppKit
@testable import CopyGlass

final class LongImageEditorLayoutTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testWideImageFitsAndKeepsAspect() {
        let rect = LongImageEditorLayout.fittedSelection(
            imagePixelSize: CGSize(width: 3024, height: 1600),
            visibleFrame: visible,
            backingScale: 2
        )
        XCTAssertLessThanOrEqual(rect.width, visible.width - LongImageEditorLayout.margin * 2 + 0.5)
        XCTAssertLessThanOrEqual(rect.maxY, visible.maxY - LongImageEditorLayout.margin + 0.5)
        XCTAssertGreaterThanOrEqual(rect.minY, visible.minY + LongImageEditorLayout.toolbarRoom)
        XCTAssertEqual(rect.width / rect.height, 3024.0 / 1600.0, accuracy: 0.01)
        XCTAssertEqual(rect.midX, visible.midX, accuracy: 0.5)
    }

    func testLongImageShrinksToFitAboveTheToolbar() {
        let rect = LongImageEditorLayout.fittedSelection(
            imagePixelSize: CGSize(width: 1200, height: 12000),
            visibleFrame: visible,
            backingScale: 2
        )
        XCTAssertLessThanOrEqual(
            rect.height,
            visible.height - LongImageEditorLayout.toolbarRoom - LongImageEditorLayout.margin * 2 + 0.5
        )
        XCTAssertGreaterThanOrEqual(rect.minY, visible.minY + LongImageEditorLayout.toolbarRoom)
        XCTAssertEqual(rect.midX, visible.midX, accuracy: 0.5)
    }

    func testSmallImageIsNotUpscaled() {
        let rect = LongImageEditorLayout.fittedSelection(
            imagePixelSize: CGSize(width: 400, height: 200),
            visibleFrame: visible,
            backingScale: 2
        )
        XCTAssertEqual(rect.width, 200, accuracy: 0.5)
        XCTAssertEqual(rect.height, 100, accuracy: 0.5)
        XCTAssertEqual(rect.midX, visible.midX, accuracy: 0.5)
    }
}
