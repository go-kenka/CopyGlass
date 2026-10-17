import XCTest
import CoreGraphics
import AppKit
@testable import CopyGlass

final class AnnotationRendererTests: XCTestCase {
    private let white = NSColor.white
    private let red = AnnotationColor(red: 1, green: 0, blue: 0)

    func testRenderWithoutShapesReturnsBaseImage() throws {
        let base = TestImage.solid(white, width: 60, height: 40)
        let rendered = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: []))
        XCTAssertEqual(rendered.width, 60)
        XCTAssertEqual(rendered.height, 40)
        XCTAssertTrue(TestImage.isClose(TestImage.pixel(rendered, x: 10, y: 10), (255, 255, 255)))
    }

    func testRectangleStrokeIsDrawnAtTheRightPlace() throws {
        let base = TestImage.solid(white, width: 200, height: 120)
        let shape = AnnotationShape(
            tool: .rectangle,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 140, y: 90)],
            color: red,
            lineWidth: 6
        )
        let rendered = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: [shape]))

        let onEdge = TestImage.pixel(rendered, x: 21, y: 55)
        XCTAssertTrue(TestImage.isClose(onEdge, (255, 0, 0), tolerance: 30), "rectangle edge should be red, got \(onEdge)")
        let interior = TestImage.pixel(rendered, x: 80, y: 55)
        XCTAssertTrue(TestImage.isClose(interior, (255, 255, 255), tolerance: 12), "rectangle interior must stay untouched")
        let outside = TestImage.pixel(rendered, x: 180, y: 110)
        XCTAssertTrue(TestImage.isClose(outside, (255, 255, 255), tolerance: 12))
    }

    func testArrowAndNumberBadgeAreDrawn() throws {
        let base = TestImage.solid(white, width: 200, height: 120)
        let arrow = AnnotationShape(
            tool: .arrow,
            points: [CGPoint(x: 10, y: 100), CGPoint(x: 180, y: 20)],
            color: AnnotationColor(red: 0, green: 0.4, blue: 1),
            lineWidth: 6
        )
        let badge = AnnotationShape(
            tool: .number,
            points: [CGPoint(x: 60, y: 60)],
            color: red,
            lineWidth: 6,
            label: 1
        )
        let rendered = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: [arrow, badge]))

        let arrowStart = TestImage.pixel(rendered, x: 11, y: 99)
        XCTAssertTrue(TestImage.isClose(arrowStart, (0, 102, 255), tolerance: 40), "arrow should start at its first point, got \(arrowStart)")
        // The centre of the badge is now covered by the centred digit, so sample the ring between
        // the digit and the rim (badge radius is 30 for lineWidth 6).
        let badgeRing = TestImage.pixel(rendered, x: 60, y: 40)
        XCTAssertTrue(TestImage.isClose(badgeRing, (255, 0, 0), tolerance: 30), "badge should be filled with its color")
    }

    func testMosaicPixelatesTheRegion() throws {
        // 1px checkerboard so pixelation is guaranteed to change the pixels.
        let context = ImageUtils.makeContext(width: 200, height: 120)!
        for y in 0..<120 {
            for x in 0..<200 {
                let isDark = (x + y) % 2 == 0
                context.setFillColor((isDark ? NSColor.black : NSColor.white).cgColor)
                context.fill(CGRect(x: x, y: 119 - y, width: 1, height: 1))
            }
        }
        let base = context.makeImage()!
        let shape = AnnotationShape(
            tool: .mosaic,
            points: [CGPoint(x: 40, y: 30), CGPoint(x: 160, y: 90)],
            color: red,
            lineWidth: 6
        )
        let rendered = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: [shape]))
        // Inside the mosaic region neighbouring pixels repeat, while the base alternated every pixel.
        var repeated = 0
        for y in 40..<80 {
            let a = TestImage.pixel(rendered, x: 60, y: y)
            let b = TestImage.pixel(rendered, x: 61, y: y)
            if TestImage.isClose(a, b, tolerance: 2) { repeated += 1 }
        }
        XCTAssertGreaterThan(repeated, 20, "mosaic should flatten neighbouring pixels")
        let untouched = TestImage.pixel(rendered, x: 10, y: 10)
        XCTAssertTrue(TestImage.isClose(untouched, (255, 255, 255), tolerance: 2) || TestImage.isClose(untouched, (0, 0, 0), tolerance: 2))
    }

    func testTextIsDrawnUprightAboveTheBaseline() throws {
        let base = TestImage.solid(white, width: 700, height: 200)
        let shape = AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 30, y: 140)],
            color: AnnotationColor(red: 0, green: 0, blue: 0),
            lineWidth: 10,
            text: "HELLO 123"
        )
        let rendered = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: [shape]))
        let above = TestImage.differingPixels(rendered, in: CGRect(x: 30, y: 85, width: 500, height: 50), from: white)
        XCTAssertGreaterThan(above, 50, "text glyphs should be drawn above the baseline")
        let below = TestImage.differingPixels(rendered, in: CGRect(x: 30, y: 150, width: 500, height: 40), from: white)
        XCTAssertEqual(below, 0, "the text must not be mirrored below the baseline")
    }

    func testHighlighterUsesTranslucentColor() throws {
        let base = TestImage.solid(white, width: 200, height: 100)
        let shape = AnnotationShape(
            tool: .highlighter,
            points: [CGPoint(x: 20, y: 50), CGPoint(x: 180, y: 50)],
            color: AnnotationColor(red: 1, green: 0.9, blue: 0),
            lineWidth: 6
        )
        let rendered = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: [shape]))
        let value = TestImage.pixel(rendered, x: 100, y: 50)
        XCTAssertLessThan(value.b, 255, "highlighter should tint the underlying pixels")
        XCTAssertGreaterThan(value.r, 200)
    }

    func testEditorModelUndoRedoAndClear() throws {
        let base = TestImage.solid(white, width: 100, height: 100)
        let model = ScreenshotEditorModel(image: base)
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.hasAnnotations)

        let first = AnnotationShape.rectangle(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 40), color: red, lineWidth: 4)
        let second = AnnotationShape.rectangle(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 80, y: 80), color: red, lineWidth: 4)
        model.commit(first)
        model.commit(second)
        XCTAssertEqual(model.shapes.count, 2)
        XCTAssertTrue(model.canUndo)
        XCTAssertEqual(model.nextNumberLabel(), 1)

        model.undo()
        XCTAssertEqual(model.shapes.count, 1)
        XCTAssertTrue(model.canRedo)
        model.redo()
        XCTAssertEqual(model.shapes.count, 2)

        model.clearAnnotations()
        XCTAssertTrue(model.shapes.isEmpty)
        model.undo()
        XCTAssertEqual(model.shapes.count, 2)

        let flattened = model.flattenedImage()
        XCTAssertEqual(flattened.width, 100)
        let stroke = TestImage.pixel(flattened, x: 10, y: 25)
        XCTAssertTrue(
            TestImage.isClose(stroke, (255, 0, 0), tolerance: 30),
            "the restored rectangle should be flattened into the exported image, got \(stroke)"
        )
    }
}
