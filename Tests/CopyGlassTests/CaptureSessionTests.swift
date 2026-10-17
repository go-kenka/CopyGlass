import XCTest
import AppKit
import CoreGraphics
@testable import CopyGlass

/// Covers the in-place capture session (Feishu-style editing state).
final class CaptureSessionTests: XCTestCase {
    private func makeSession(width: Int = 200, height: Int = 120) -> CaptureSession {
        CaptureSession(image: TestImage.solid(.white, width: width, height: height))
    }

    func testCommitUndoRedoAndBadgeNumbering() {
        let session = makeSession()
        XCTAssertFalse(session.canUndo)
        XCTAssertEqual(session.nextBadge, 1)

        let rect = AnnotationShape.rectangle(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 60), color: AnnotationColor.palette[0], lineWidth: 4)
        session.commit(rect)
        XCTAssertEqual(session.shapes.count, 1)
        XCTAssertTrue(session.hasAnnotations)

        let badge = AnnotationShape(tool: .number, points: [CGPoint(x: 40, y: 40)], color: AnnotationColor.palette[0], lineWidth: 4, label: session.nextBadge)
        session.commit(badge)
        XCTAssertEqual(badge.label, 1)
        XCTAssertEqual(session.nextBadge, 2)

        session.undo()
        XCTAssertEqual(session.shapes.count, 1)
        XCTAssertEqual(session.nextBadge, 1)
        XCTAssertTrue(session.canRedo)

        session.redo()
        XCTAssertEqual(session.shapes.count, 2)

        session.clearAnnotations()
        XCTAssertTrue(session.shapes.isEmpty)
        session.undo()
        XCTAssertEqual(session.shapes.count, 2)
    }

    func testFlattenedImageContainsAnnotations() {
        let session = makeSession()
        let rect = AnnotationShape.rectangle(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 80, y: 80), color: AnnotationColor(red: 1, green: 0, blue: 0), lineWidth: 6)
        session.commit(rect)

        let flattened = session.flattenedImage()
        XCTAssertEqual(flattened.width, 200)
        XCTAssertEqual(flattened.height, 120)
        let stroke = TestImage.pixel(flattened, x: 11, y: 45)
        XCTAssertTrue(TestImage.isClose(stroke, (255, 0, 0), tolerance: 30), "expected the rectangle stroke, got \(stroke)")
        let untouched = TestImage.pixel(flattened, x: 150, y: 20)
        XCTAssertTrue(TestImage.isClose(untouched, (255, 255, 255), tolerance: 6))
    }

    func testSessionNotifiesOverlayOnEveryChange() {
        let session = makeSession()
        var redraws = 0
        session.onNeedsDisplay = { redraws += 1 }

        session.commit(AnnotationShape.rectangle(from: .zero, to: CGPoint(x: 20, y: 20), color: AnnotationColor.palette[0], lineWidth: 4))
        XCTAssertEqual(redraws, 1)
        session.undo()
        XCTAssertEqual(redraws, 2)
        session.redo()
        XCTAssertEqual(redraws, 3)
        session.clearAnnotations()
        XCTAssertEqual(redraws, 4)
    }

    /// Recognition runs once per capture: opening the text panel again must be instant.
    func testRecognitionRunsOnlyOncePerCapture() throws {
        let base = TestImage.solid(.white, width: 760, height: 220)
        let shape = AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 40, y: 160)],
            color: AnnotationColor(red: 0, green: 0, blue: 0),
            lineWidth: 12,
            text: "CopyGlass 7"
        )
        let image = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: [shape]))
        let session = CaptureSession(image: image)

        session.recognizeText()
        XCTAssertTrue(session.isRecognizing)

        // Wait for the background recognition to finish.
        let deadline = Date().addingTimeInterval(90)
        while session.isRecognizing, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(session.isRecognizing, "recognition should have finished")
        let first = try XCTUnwrap(session.ocrResult)
        XCTAssertFalse(first.isEmpty)

        // Second call must reuse the cached result instead of starting another request.
        session.recognizeText()
        XCTAssertFalse(session.isRecognizing, "the second call must not start a new request")
        XCTAssertEqual(session.ocrResult?.blocks.count, first.blocks.count)
    }

    /// While the inline editor is open the annotation is drawn by the text field only, otherwise
    /// the two renderings overlap and the text looks ghosted.
    func testShapeBeingEditedIsHiddenFromTheCanvas() {
        let session = CaptureSession(image: TestImage.solid(.white, width: 400, height: 200))
        let text = AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 40, y: 120)],
            color: AnnotationColor(red: 0, green: 0, blue: 0),
            lineWidth: 4,
            text: "CopyGlass"
        )
        session.commit(text)
        XCTAssertEqual(session.renderableShapes.count, 1)

        session.setTextEditingShape(text.id)
        XCTAssertTrue(session.renderableShapes.isEmpty, "the editable field draws the text instead")
        XCTAssertNotNil(session.shape(with: text.id), "the annotation itself is kept until commit")

        session.setTextEditingShape(nil)
        XCTAssertEqual(session.renderableShapes.count, 1)
    }

    /// Re-editing a text annotation really changes the exported image.
    func testReplacingEditedTextUpdatesTheFlattenedImage() throws {
        let session = CaptureSession(image: TestImage.solid(.white, width: 700, height: 220))
        var text = AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 40, y: 150)],
            color: AnnotationColor(red: 0, green: 0, blue: 0),
            lineWidth: 8,
            text: "AAAA"
        )
        session.commit(text)
        let area = CGRect(x: 30, y: 50, width: 640, height: 130)
        let before = TestImage.differingPixels(try XCTUnwrap(AnnotationRenderer.render(base: session.image, shapes: session.shapes)), in: area, from: .white)

        text.text = "AAAAAAAAAAAAAAAAAAAA"
        session.replace(text)
        let after = TestImage.differingPixels(try XCTUnwrap(AnnotationRenderer.render(base: session.image, shapes: session.shapes)), in: area, from: .white)
        XCTAssertGreaterThan(after, before, "the longer text must appear in the output")
    }

    /// Recognized text areas stay hidden until the user turns the highlight on.
    func testOCRHighlightIsOffByDefault() throws {
        let base = TestImage.solid(.white, width: 760, height: 220)
        let shape = AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 40, y: 160)],
            color: AnnotationColor(red: 0, green: 0, blue: 0),
            lineWidth: 12,
            text: "CopyGlass 9"
        )
        let image = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: [shape]))
        let session = CaptureSession(image: image)

        XCTAssertFalse(session.showOCRBoxes, "the highlight toggle must default to off")
        XCTAssertTrue(session.ocrBoxes.isEmpty)

        session.recognizeText()
        let deadline = Date().addingTimeInterval(90)
        while session.isRecognizing, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let result = try XCTUnwrap(session.ocrResult)
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(session.showOCRBoxes, "recognition must not turn the highlight on by itself")
        XCTAssertTrue(session.ocrBoxes.isEmpty, "no highlight while the toggle is off")

        session.showOCRBoxes = true
        XCTAssertEqual(session.ocrBoxes.count, result.blocks.count)
    }

    func testCanvasTransformMapsSelectionOntoOverlay() {
        // A 200x120 crop displayed inside a 400x240 selection: 2x scale, top-left origin at (50, 30).
        let transform = CanvasTransform(
            scale: 2,
            origin: CGPoint(x: 50, y: 30),
            imageSize: CGSize(width: 200, height: 120)
        )
        let topLeft = transform.viewPoint(from: .zero)
        XCTAssertEqual(topLeft.x, 50, accuracy: 0.001)
        XCTAssertEqual(topLeft.y, 30 + 240, accuracy: 0.001)

        let roundTrip = transform.imagePoint(from: CGPoint(x: 150, y: 90))
        XCTAssertEqual(roundTrip.x, 50, accuracy: 0.001)
        XCTAssertEqual(roundTrip.y, 90, accuracy: 0.001)
    }
}
