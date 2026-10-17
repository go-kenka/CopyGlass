import XCTest
import CoreGraphics
@testable import CopyGlass

/// The click semantics for editing annotations.
final class AnnotationPressIntentTests: XCTestCase {
    private func rectangle() -> AnnotationShape {
        AnnotationShape(
            tool: .rectangle,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 120, y: 80)],
            color: AnnotationColor.palette[0],
            lineWidth: 4
        )
    }

    private func text() -> AnnotationShape {
        AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 40, y: 100)],
            color: AnnotationColor.palette[0],
            lineWidth: 4,
            text: "CopyGlass"
        )
    }

    func testClickingTextStartsEditingEvenWithAPointer() throws {
        let shape = text()
        let bounds = try XCTUnwrap(AnnotationRenderer.textBounds(for: shape))
        let intent = AnnotationHitTester.pressIntent(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            shapes: [shape],
            selected: nil,
            tool: .select,
            optionHeld: false,
            screenScale: 1
        )
        XCTAssertEqual(intent, .editText(id: shape.id))
    }

    func testClickingOtherAnnotationsMovesThem() {
        let shape = rectangle()
        let intent = AnnotationHitTester.pressIntent(
            at: CGPoint(x: 70, y: 50),
            shapes: [shape],
            selected: nil,
            tool: .rectangle,
            optionHeld: false,
            screenScale: 1
        )
        XCTAssertEqual(intent, .move(id: shape.id))
    }

    func testHandleWinsOverTheShapeBody() {
        let shape = rectangle()
        let intent = AnnotationHitTester.pressIntent(
            at: CGPoint(x: 20, y: 20),
            shapes: [shape],
            selected: shape,
            tool: .select,
            optionHeld: false,
            screenScale: 1
        )
        XCTAssertEqual(intent, .resize(id: shape.id, handle: .topLeft))
    }

    func testEmptyAreaDrawsWithADrawingToolAndDoesNothingWithThePointer() {
        let empty = AnnotationHitTester.pressIntent(
            at: CGPoint(x: 300, y: 300),
            shapes: [rectangle()],
            selected: nil,
            tool: .arrow,
            optionHeld: false,
            screenScale: 1
        )
        XCTAssertEqual(empty, .draw)

        let pointer = AnnotationHitTester.pressIntent(
            at: CGPoint(x: 300, y: 300),
            shapes: [rectangle()],
            selected: nil,
            tool: .select,
            optionHeld: false,
            screenScale: 1
        )
        XCTAssertEqual(pointer, .none)
    }

    func testOptionAlwaysDrawsOnTopOfAnExistingAnnotation() {
        let shape = rectangle()
        let intent = AnnotationHitTester.pressIntent(
            at: CGPoint(x: 70, y: 50),
            shapes: [shape],
            selected: shape,
            tool: .rectangle,
            optionHeld: true,
            screenScale: 1
        )
        XCTAssertEqual(intent, .draw)
    }

    func testHitToleranceIsIndependentOfTheScreenScale() {
        // The shape's own tolerance is max(6, lineWidth * 1.5) = 6 image pixels, whatever the scale.
        let shape = rectangle()
        let onEdge = AnnotationHitTester.pressIntent(
            at: CGPoint(x: 124, y: 50),
            shapes: [shape],
            selected: nil,
            tool: .select,
            optionHeld: false,
            screenScale: 2
        )
        XCTAssertEqual(onEdge, .move(id: shape.id))

        let outside = AnnotationHitTester.pressIntent(
            at: CGPoint(x: 130, y: 50),
            shapes: [shape],
            selected: nil,
            tool: .select,
            optionHeld: false,
            screenScale: 2
        )
        XCTAssertEqual(outside, .none)
    }
}
