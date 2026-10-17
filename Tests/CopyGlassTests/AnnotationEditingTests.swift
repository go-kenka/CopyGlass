import XCTest
import AppKit
import CoreGraphics
@testable import CopyGlass

/// Re-editing existing annotations: hit testing, moving, resizing, deleting.
final class AnnotationEditingTests: XCTestCase {
    private func rectangleShape() -> AnnotationShape {
        AnnotationShape(
            tool: .rectangle,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 120, y: 80)],
            color: AnnotationColor.palette[0],
            lineWidth: 4
        )
    }

    func testRectangleHitTestCoversItsAreaButNotTheOutside() {
        let shape = rectangleShape()
        XCTAssertTrue(AnnotationHitTester.contains(shape, imagePoint: CGPoint(x: 70, y: 50)))
        XCTAssertTrue(AnnotationHitTester.contains(shape, imagePoint: CGPoint(x: 21, y: 21)))
        XCTAssertFalse(AnnotationHitTester.contains(shape, imagePoint: CGPoint(x: 200, y: 50)))
    }

    func testEllipseHitTestIgnoresTheCornersOfItsBounds() {
        let shape = AnnotationShape(
            tool: .ellipse,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)],
            color: AnnotationColor.palette[0],
            lineWidth: 4
        )
        XCTAssertTrue(AnnotationHitTester.contains(shape, imagePoint: CGPoint(x: 50, y: 50)))
        XCTAssertFalse(AnnotationHitTester.contains(shape, imagePoint: CGPoint(x: 2, y: 2)))
    }

    func testArrowIsHitNearItsShaftOnly() {
        let arrow = AnnotationShape(
            tool: .arrow,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 110)],
            color: AnnotationColor.palette[0],
            lineWidth: 4
        )
        XCTAssertTrue(AnnotationHitTester.contains(arrow, imagePoint: CGPoint(x: 60, y: 62)))
        XCTAssertFalse(AnnotationHitTester.contains(arrow, imagePoint: CGPoint(x: 100, y: 20)))
    }

    func testPenIsHitAlongItsPolyline() {
        let pen = AnnotationShape(
            tool: .pen,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 10), CGPoint(x: 60, y: 60)],
            color: AnnotationColor.palette[0],
            lineWidth: 3
        )
        XCTAssertTrue(AnnotationHitTester.contains(pen, imagePoint: CGPoint(x: 35, y: 12)))
        XCTAssertTrue(AnnotationHitTester.contains(pen, imagePoint: CGPoint(x: 62, y: 40)))
        XCTAssertFalse(AnnotationHitTester.contains(pen, imagePoint: CGPoint(x: 90, y: 45)))
    }

    func testTextHitTestMatchesTheDrawnGlyphs() throws {
        let shape = AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 40, y: 100)],
            color: AnnotationColor.palette[0],
            lineWidth: 6,
            text: "CopyGlass"
        )
        let bounds = try XCTUnwrap(AnnotationRenderer.textBounds(for: shape))
        XCTAssertGreaterThan(bounds.width, 40)
        XCTAssertTrue(AnnotationHitTester.contains(shape, imagePoint: CGPoint(x: bounds.midX, y: bounds.midY)))
        XCTAssertFalse(AnnotationHitTester.contains(shape, imagePoint: CGPoint(x: bounds.maxX + 40, y: bounds.midY)))
        // The box sits above the baseline the text was placed at (descenders hang below it).
        XCTAssertLessThan(bounds.midY, 100)
        XCTAssertLessThan(bounds.minY, 80)

        let capsShape = AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 40, y: 100)],
            color: AnnotationColor.palette[0],
            lineWidth: 6,
            text: "COPY"
        )
        let capsBounds = try XCTUnwrap(AnnotationRenderer.textBounds(for: capsShape))
        // CoreText reports the line box (cap height plus the font descent), which is what we want for
        // clicking: the box covers the glyphs and stops before the next line.
        let fontSize = AnnotationRenderer.fontSize(forLineWidth: capsShape.lineWidth)
        XCTAssertLessThan(capsBounds.maxY, 100 + fontSize * 0.4, "the box must not extend far below the baseline")
        XCTAssertGreaterThan(capsBounds.minY, 100 - fontSize, "the box must cover the glyphs above the baseline")
        XCTAssertLessThan(capsBounds.midY, 100)
    }

    func testNumberBadgeIsHitWithinItsCircle() {
        let badge = AnnotationShape(tool: .number, points: [CGPoint(x: 100, y: 100)], color: AnnotationColor.palette[0], lineWidth: 4, label: 1)
        XCTAssertTrue(AnnotationHitTester.contains(badge, imagePoint: CGPoint(x: 110, y: 100)))
        XCTAssertFalse(AnnotationHitTester.contains(badge, imagePoint: CGPoint(x: 200, y: 100)))
    }

    func testTopmostAnnotationWinsTheHitTest() {
        let first = rectangleShape()
        let second = AnnotationShape(
            tool: .rectangle,
            points: [CGPoint(x: 60, y: 40), CGPoint(x: 160, y: 100)],
            color: AnnotationColor.palette[1],
            lineWidth: 4
        )
        let hit = AnnotationHitTester.hitTest([first, second], imagePoint: CGPoint(x: 80, y: 60))
        XCTAssertEqual(hit?.id, second.id)
    }

    func testTranslateMovesEveryPoint() {
        let moved = AnnotationHitTester.translate(rectangleShape(), by: CGSize(width: 10, height: -5))
        XCTAssertEqual(moved.points[0], CGPoint(x: 30, y: 15))
        XCTAssertEqual(moved.points[1], CGPoint(x: 130, y: 75))
    }

    func testResizeRectangleThroughACornerHandle() {
        let resized = AnnotationHitTester.resize(rectangleShape(), handle: .topLeft, to: CGPoint(x: 0, y: 0))
        XCTAssertEqual(resized.points[0], CGPoint(x: 0, y: 0))
        XCTAssertEqual(resized.points[1], CGPoint(x: 120, y: 80))

        let widened = AnnotationHitTester.resize(rectangleShape(), handle: .right, to: CGPoint(x: 200, y: 0))
        XCTAssertEqual(widened.points[1].x, 200)
        XCTAssertEqual(widened.points[1].y, 80)
    }

    func testArrowHandlesMoveTheEndpoints() throws {
        let arrow = AnnotationShape(
            tool: .arrow,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)],
            color: AnnotationColor.palette[0],
            lineWidth: 4
        )
        let handles = AnnotationHitTester.handles(for: arrow)
        XCTAssertEqual(handles.count, 2)

        let resized = AnnotationHitTester.resize(arrow, handle: .end, to: CGPoint(x: 200, y: 30))
        XCTAssertEqual(resized.points.first, CGPoint(x: 10, y: 10))
        XCTAssertEqual(resized.points.last, CGPoint(x: 200, y: 30))

        let handle = AnnotationHitTester.handle(at: CGPoint(x: 12, y: 12), for: arrow, tolerance: 5)
        XCTAssertEqual(handle, .start)
    }

    func testOnlyResizableShapesExposeHandles() {
        XCTAssertEqual(AnnotationHitTester.handles(for: rectangleShape()).count, 8)
        let pen = AnnotationShape(tool: .pen, points: [CGPoint(x: 1, y: 1), CGPoint(x: 20, y: 20)], color: AnnotationColor.palette[0], lineWidth: 3)
        XCTAssertTrue(AnnotationHitTester.handles(for: pen).isEmpty)
        let text = AnnotationShape(tool: .text, points: [CGPoint(x: 5, y: 5)], color: AnnotationColor.palette[0], lineWidth: 4, text: "hi")
        XCTAssertTrue(AnnotationHitTester.handles(for: text).isEmpty)
    }

    func testSessionSelectionMoveUndoNudgeAndDelete() {
        let session = CaptureSession(image: TestImage.solid(.white, width: 300, height: 200))
        let shape = rectangleShape()
        session.commit(shape)
        XCTAssertEqual(session.selectedShapeID, shape.id, "a freshly drawn annotation is selected")

        session.beginInteractiveEdit()
        session.applyInteractiveChange(AnnotationHitTester.translate(shape, by: CGSize(width: 40, height: 0)))
        session.endInteractiveEdit()
        XCTAssertEqual(session.shapes.first?.points.first?.x, 60)

        session.undo()
        XCTAssertEqual(session.shapes.first?.points.first?.x, 20, "one drag is one undo step")

        session.select(shape.id)
        session.nudgeSelectedShape(by: CGSize(width: 0, height: 5))
        XCTAssertEqual(session.shapes.first?.points.first?.y, 25)

        session.select(shape.id)
        session.removeSelectedShape()
        XCTAssertTrue(session.shapes.isEmpty)
        XCTAssertNil(session.selectedShapeID)
    }

    func testHoverAndSelectionPublishState() {
        let session = CaptureSession(image: TestImage.solid(.white, width: 300, height: 200))
        let shape = rectangleShape()
        session.commit(shape)
        XCTAssertEqual(session.tool, .select, "the pointer tool is the default")

        session.setHoveredShape(shape.id)
        XCTAssertEqual(session.hoveredShape?.id, shape.id)
        session.setHoveredShape(nil)
        XCTAssertNil(session.hoveredShape)
    }
}
