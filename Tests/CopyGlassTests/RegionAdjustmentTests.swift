import XCTest
import AppKit
import CoreGraphics
@testable import CopyGlass

/// Covers editing of the capture frame itself (moving/resizing it after it was drawn) and the
/// annotation remapping that keeps annotations on the same spot of the frozen screen.
final class RegionAdjustmentTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 200, height: 100)

    // MARK: - Handles

    func testHandlesSitOnTheFrameEdgesAndCorners() {
        let handles = SelectionAdjustment.handles(for: frame)
        XCTAssertEqual(handles.count, 8)
        let byHandle = Dictionary(uniqueKeysWithValues: handles.map { ($0.handle, $0.point) })
        // Cocoa coordinates: "top" is the largest Y.
        XCTAssertEqual(byHandle[.topLeft], CGPoint(x: 100, y: 200))
        XCTAssertEqual(byHandle[.top], CGPoint(x: 200, y: 200))
        XCTAssertEqual(byHandle[.right], CGPoint(x: 300, y: 150))
        XCTAssertEqual(byHandle[.bottomRight], CGPoint(x: 300, y: 100))
        XCTAssertEqual(byHandle[.bottom], CGPoint(x: 200, y: 100))
        XCTAssertEqual(byHandle[.left], CGPoint(x: 100, y: 150))
    }

    func testHandleHitTestPicksTheNearestHandleInsideTheTolerance() {
        XCTAssertEqual(SelectionAdjustment.handle(at: CGPoint(x: 300, y: 200), in: frame), .topRight)
        // Slightly off the corner, still within the grab tolerance.
        XCTAssertEqual(SelectionAdjustment.handle(at: CGPoint(x: 305, y: 196), in: frame), .topRight)
        // Middle of an edge.
        XCTAssertEqual(SelectionAdjustment.handle(at: CGPoint(x: 200, y: 100), in: frame), .bottom)
        // Centre of the frame is not a handle.
        XCTAssertNil(SelectionAdjustment.handle(at: CGPoint(x: 200, y: 150), in: frame))
        XCTAssertNil(SelectionAdjustment.handle(at: CGPoint(x: 500, y: 500), in: frame))

        // On a small frame two handles can both be inside the grab tolerance; the nearest wins.
        let small = CGRect(x: 0, y: 0, width: 24, height: 24)
        XCTAssertEqual(SelectionAdjustment.handle(at: CGPoint(x: 5, y: 24), in: small), .topLeft)
        XCTAssertEqual(SelectionAdjustment.handle(at: CGPoint(x: 8, y: 24), in: small), .top)
    }

    func testSmallFramesShrinkTheGrabToleranceSoTheirInteriorStaysUsable() {
        XCTAssertEqual(SelectionAdjustment.handleTolerance(for: frame), SelectionAdjustment.handleTolerance)
        let tiny = CGRect(x: 0, y: 0, width: 18, height: 18)
        XCTAssertLessThan(SelectionAdjustment.handleTolerance(for: tiny), SelectionAdjustment.handleTolerance)
        // The middle of a tiny frame is not a handle: it can still be dragged/drawn on.
        XCTAssertNil(SelectionAdjustment.handle(at: CGPoint(x: 9, y: 9), in: tiny))
    }

    // MARK: - Resize / move

    func testResizingAnEdgeKeepsTheOppositeEdgeFixed() {
        let left = SelectionAdjustment.resized(frame, handle: .left, to: CGPoint(x: 150, y: 0))
        XCTAssertEqual(left, CGRect(x: 150, y: 100, width: 150, height: 100))

        let top = SelectionAdjustment.resized(frame, handle: .top, to: CGPoint(x: 0, y: 250))
        XCTAssertEqual(top, CGRect(x: 100, y: 100, width: 200, height: 150))

        let topLeft = SelectionAdjustment.resized(frame, handle: .topLeft, to: CGPoint(x: 120, y: 240))
        XCTAssertEqual(topLeft, CGRect(x: 120, y: 100, width: 180, height: 140))

        let bottomRight = SelectionAdjustment.resized(frame, handle: .bottomRight, to: CGPoint(x: 260, y: 140))
        XCTAssertEqual(bottomRight, CGRect(x: 100, y: 140, width: 160, height: 60))
    }

    func testResizingPastTheOppositeEdgeStopsAtTheMinimumSize() {
        let squeezed = SelectionAdjustment.resized(frame, handle: .right, to: CGPoint(x: 0, y: 0))
        XCTAssertEqual(squeezed.width, SelectionAdjustment.minimumSize, accuracy: 0.001)
        XCTAssertEqual(squeezed.minX, frame.minX, "the fixed edge must not move")

        let squeezedTop = SelectionAdjustment.resized(frame, handle: .topLeft, to: CGPoint(x: 500, y: 0))
        XCTAssertEqual(squeezedTop.width, SelectionAdjustment.minimumSize, accuracy: 0.001)
        XCTAssertEqual(squeezedTop.height, SelectionAdjustment.minimumSize, accuracy: 0.001)
    }

    func testMovingAndClampingKeepsTheFrameOnScreen() {
        let moved = SelectionAdjustment.moved(frame, by: CGSize(width: 30, height: -20))
        XCTAssertEqual(moved, CGRect(x: 130, y: 80, width: 200, height: 100))

        let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let clamped = SelectionAdjustment.clamped(CGRect(x: -50, y: 900, width: 200, height: 100), to: bounds)
        XCTAssertEqual(clamped, CGRect(x: 0, y: 882, width: 200, height: 100))

        let tooLarge = SelectionAdjustment.clamped(CGRect(x: -50, y: -50, width: 4000, height: 3000), to: bounds)
        XCTAssertEqual(tooLarge, bounds)
    }

    // MARK: - Annotation remapping

    /// Moving the capture frame must keep a point of the frozen screen at the same screen position.
    func testAnnotationPointsStayOnTheFrozenScreenWhenTheFrameMoves() {
        let transform = SelectionAdjustment.imagePointTransform(
            from: CGRect(x: 100, y: 200, width: 200, height: 100),
            oldImageSize: CGSize(width: 400, height: 200),
            to: CGRect(x: 50, y: 150, width: 400, height: 200),
            newImageSize: CGSize(width: 800, height: 400)
        )
        let mapped = transform(CGPoint(x: 40, y: 30))
        XCTAssertEqual(mapped.x, 140, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 130, accuracy: 0.001)
    }

    func testAnnotationRemapHandlesADifferentPixelScale() {
        // Same frame, but the new crop has half the pixels (a display with a different scale).
        let transform = SelectionAdjustment.imagePointTransform(
            from: CGRect(x: 100, y: 200, width: 200, height: 100),
            oldImageSize: CGSize(width: 400, height: 200),
            to: CGRect(x: 100, y: 200, width: 200, height: 100),
            newImageSize: CGSize(width: 200, height: 100)
        )
        // The centre of the old crop maps onto the centre of the new crop.
        XCTAssertEqual(transform(CGPoint(x: 200, y: 100)).x, 100, accuracy: 0.001)
        XCTAssertEqual(transform(CGPoint(x: 200, y: 100)).y, 50, accuracy: 0.001)
    }

    func testDegenerateTransformsLeavePointsAlone() {
        let transform = SelectionAdjustment.imagePointTransform(
            from: .zero,
            oldImageSize: .zero,
            to: .zero,
            newImageSize: .zero
        )
        XCTAssertEqual(transform(CGPoint(x: 12, y: 34)), CGPoint(x: 12, y: 34))
    }

    func testVisualScaleCompensatesForADifferentPixelDensity() {
        let sameScale = SelectionAdjustment.imagePixelScaleRatio(
            from: frame, oldImageSize: CGSize(width: 400, height: 200),
            to: frame, newImageSize: CGSize(width: 400, height: 200)
        )
        XCTAssertEqual(sameScale, 1, accuracy: 0.0001)

        // The new crop has half the pixels per point (2x display -> 1x display).
        let halfDensity = SelectionAdjustment.imagePixelScaleRatio(
            from: frame, oldImageSize: CGSize(width: 400, height: 200),
            to: frame, newImageSize: CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(halfDensity, 0.5, accuracy: 0.0001)
    }

    // MARK: - Capture session

    func testUpdatingTheCropRemapsAnnotationsAndTheirUndoHistory() {
        let session = CaptureSession(image: TestImage.solid(.white, width: 200, height: 100))
        let first = AnnotationShape(
            tool: .rectangle,
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 40)],
            color: AnnotationColor.palette[0],
            lineWidth: 4
        )
        session.commit(first)
        let second = AnnotationShape(
            tool: .rectangle,
            points: [CGPoint(x: 60, y: 20), CGPoint(x: 90, y: 50)],
            color: AnnotationColor.palette[1],
            lineWidth: 4
        )
        session.commit(second)
        session.panel = .ocr
        session.statusMessage = "stale"

        let newImage = TestImage.solid(.white, width: 400, height: 200)
        session.updateCapture(image: newImage, remapping: { point in
            CGPoint(x: point.x + 20, y: point.y + 10)
        }, visualScale: 0.5)

        XCTAssertEqual(session.image.width, 400)
        XCTAssertEqual(session.shapes.count, 2)
        XCTAssertEqual(session.shapes[0].points[0], CGPoint(x: 30, y: 20))
        XCTAssertEqual(session.shapes[1].points[1], CGPoint(x: 110, y: 60))
        XCTAssertEqual(session.shapes[0].lineWidth, 2, "a different pixel density must not change the stroke's visual size")
        XCTAssertEqual(session.shapes[0].blockSize, 7, accuracy: 0.001)
        XCTAssertEqual(session.panel, .tools, "text results belong to the old crop")
        XCTAssertNil(session.statusMessage)

        // The undo history was remapped too, so undoing does not move annotations back into the
        // old crop's coordinate space.
        session.undo()
        XCTAssertEqual(session.shapes.count, 1)
        XCTAssertEqual(session.shapes[0].points[0], CGPoint(x: 30, y: 20))
        XCTAssertEqual(session.shapes[0].lineWidth, 2)

        // ... and so was the redo history.
        session.redo()
        XCTAssertEqual(session.shapes.count, 2)
        XCTAssertEqual(session.shapes[1].points[1], CGPoint(x: 110, y: 60))
        XCTAssertEqual(session.shapes[1].lineWidth, 2)
    }
}
