import XCTest
import CoreGraphics
import AppKit
import Vision
@testable import CopyGlass

final class OCRServiceTests: XCTestCase {
    func testVisionSupportsChineseAndEnglishRecognition() throws {
        let supported = try VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate,
            revision: VNRecognizeTextRequestRevision3
        )
        XCTAssertTrue(supported.contains("zh-Hans"), "Vision should support Simplified Chinese, got \(supported)")
        XCTAssertTrue(supported.contains("en-US") || supported.contains("en"), "Vision should support English")
        // The service must keep the requested languages instead of falling back to the default set.
        let filtered = OCRService.defaultLanguages.filter { supported.contains($0) }
        XCTAssertTrue(filtered.contains("zh-Hans"))
    }

    func testRecognizesRenderedText() throws {
        let base = TestImage.solid(.white, width: 760, height: 220)
        let shape = AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 40, y: 160)],
            color: AnnotationColor(red: 0, green: 0, blue: 0),
            lineWidth: 12,
            text: "CopyGlass 123"
        )
        let image = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: [shape]))

        let result: OCRResult
        do {
            result = try OCRService.recognize(image: image)
        } catch {
            throw XCTSkip("Vision text recognition unavailable in this environment: \(error)")
        }

        XCTAssertFalse(result.blocks.isEmpty, "Vision should recognize the rendered text")
        let joined = result.plainText.uppercased().replacingOccurrences(of: " ", with: "")
        XCTAssertTrue(joined.contains("COPYGLASS"), "unexpected recognized text: \(result.plainText)")

        // Bounding boxes are reported in top-left image coordinates.
        let block = try XCTUnwrap(result.blocks.first)
        XCTAssertGreaterThan(block.pixelBox.minY, 60)
        XCTAssertLessThan(block.pixelBox.maxY, 190)
        XCTAssertGreaterThanOrEqual(block.normalizedBox.minY, 0)
        XCTAssertLessThanOrEqual(block.normalizedBox.maxY, 1)
    }

    /// Warming up must be safe to call repeatedly and must not break recognition.
    func testWarmUpIsIdempotentAndRecognitionStillWorks() throws {
        OCRService.warmUpIfNeeded()
        OCRService.warmUpIfNeeded()
        OCRService.warmUpIfNeeded()

        let base = TestImage.solid(.white, width: 760, height: 220)
        let shape = AnnotationShape(
            tool: .text,
            points: [CGPoint(x: 40, y: 160)],
            color: AnnotationColor(red: 0, green: 0, blue: 0),
            lineWidth: 12,
            text: "Warmup 42"
        )
        let image = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: [shape]))
        let result = try OCRService.recognize(image: image)
        XCTAssertFalse(result.blocks.isEmpty, "recognition must still work after pre-warming")
    }

    func testEmptyImageProducesNoText() throws {
        let blank = TestImage.solid(.white, width: 200, height: 120)
        guard let result = try? OCRService.recognize(image: blank) else {
            throw XCTSkip("Vision text recognition unavailable in this environment")
        }
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertEqual(result.plainText, "")
    }
}
