import XCTest
import CoreGraphics
import AppKit
@testable import CopyGlass

final class ImageStitcherTests: XCTestCase {
    private let width = 40

    private func assertClose(_ value: Int, _ expected: Int, accuracy: Int = 1, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(
            abs(value - expected),
            accuracy,
            message.isEmpty ? "\(value) is not within \(accuracy) of \(expected)" : message,
            file: file,
            line: line
        )
    }

    func testCropUsesTopLeftOrigin() throws {
        let document = TestImage.rows(width: width, colors: TestImage.documentRows(count: 200))
        let cropped = try XCTUnwrap(ImageUtils.crop(document, topLeftRect: CGRect(x: 0, y: 100, width: CGFloat(width), height: 50)))
        XCTAssertEqual(cropped.height, 50)

        let firstRow = TestImage.pixel(cropped, x: 0, y: 0)
        let expectedFirst = TestImage.colorComponents(TestImage.documentColor(row: 100))
        XCTAssertTrue(TestImage.isClose(firstRow, expectedFirst), "crop must start at the requested top-left row")

        let lastRow = TestImage.pixel(cropped, x: 0, y: 49)
        let expectedLast = TestImage.colorComponents(TestImage.documentColor(row: 149))
        XCTAssertTrue(TestImage.isClose(lastRow, expectedLast))
    }

    func testSignaturePreservesRowOrder() throws {
        let document = TestImage.rows(width: width, colors: TestImage.documentRows(count: 120))
        let signature = try XCTUnwrap(ImageStitcher.signature(of: document, sampleWidth: 32))
        XCTAssertEqual(signature.height, 120)
        XCTAssertNotEqual(signature.gray[0], signature.gray[signature.width * 119])
    }

    func testFindMatchAndComposeWithoutHeader() throws {
        let document = TestImage.rows(width: width, colors: TestImage.documentRows(count: 400))
        let first = try XCTUnwrap(ImageUtils.crop(document, topLeftRect: CGRect(x: 0, y: 0, width: CGFloat(width), height: 200)))
        let second = try XCTUnwrap(ImageUtils.crop(document, topLeftRect: CGRect(x: 0, y: 120, width: CGFloat(width), height: 200)))

        let firstSignature = try XCTUnwrap(ImageStitcher.signature(of: first))
        let secondSignature = try XCTUnwrap(ImageStitcher.signature(of: second))

        let match = try XCTUnwrap(ImageStitcher.findMatch(previous: firstSignature, next: secondSignature))
        // The bottom window of the first frame starts 134 rows in and lands on row 14 of the
        // second frame after scrolling 120 rows.
        XCTAssertEqual(match.length, 66)
        assertClose(match.nextStart, 14)
        assertClose(match.appendedRows(nextHeight: 200), 120)

        let composed = try XCTUnwrap(ImageStitcher.compose(previous: first, next: second, match: match))
        XCTAssertEqual(composed.height, 320)
        for row in [0, 150, 250, 319] {
            let value = TestImage.pixel(composed, x: 5, y: row)
            let expected = TestImage.colorComponents(TestImage.documentColor(row: row))
            XCTAssertTrue(TestImage.isClose(value, expected), "row \(row) should match the original document")
        }
    }

    func testFindMatchWithStickyHeader() throws {
        let headerHeight = 20
        let scroll = 60
        let visibleContent = 180
        var firstColors = Array(repeating: NSColor.black, count: headerHeight)
        firstColors.append(contentsOf: TestImage.documentRows(count: visibleContent, start: 0))
        var secondColors = Array(repeating: NSColor.black, count: headerHeight)
        secondColors.append(contentsOf: TestImage.documentRows(count: visibleContent, start: scroll))

        let first = TestImage.rows(width: width, colors: firstColors)
        let second = TestImage.rows(width: width, colors: secondColors)

        let firstSignature = try XCTUnwrap(ImageStitcher.signature(of: first))
        let secondSignature = try XCTUnwrap(ImageStitcher.signature(of: second))

        let match = try XCTUnwrap(ImageStitcher.findMatch(previous: firstSignature, next: secondSignature))
        assertClose(match.appendedRows(nextHeight: 200), scroll)

        let composed = try XCTUnwrap(ImageStitcher.compose(previous: first, next: second, match: match))
        XCTAssertEqual(composed.height, 200 + scroll)
        let headerPixel = TestImage.pixel(composed, x: 3, y: 0)
        XCTAssertTrue(TestImage.isClose(headerPixel, TestImage.colorComponents(.black)))
        let lastPixel = TestImage.pixel(composed, x: 3, y: composed.height - 1)
        let expectedLast = TestImage.colorComponents(TestImage.documentColor(row: visibleContent + scroll - 1))
        XCTAssertTrue(TestImage.isClose(lastPixel, expectedLast))
    }

    func testIdenticalFramesAreDetected() throws {
        let frame = TestImage.rows(width: width, colors: TestImage.documentRows(count: 120))
        let other = TestImage.rows(width: width, colors: TestImage.documentRows(count: 120, start: 40))
        let a = try XCTUnwrap(ImageStitcher.signature(of: frame))
        let identical = try XCTUnwrap(ImageStitcher.signature(of: frame))
        let shifted = try XCTUnwrap(ImageStitcher.signature(of: other))
        XCTAssertTrue(ImageStitcher.areNearlyIdentical(a, identical))
        XCTAssertFalse(ImageStitcher.areNearlyIdentical(a, shifted))
    }

    func testNoMatchForUnrelatedFrames() throws {
        let a = try XCTUnwrap(ImageStitcher.signature(of: TestImage.rows(width: width, colors: TestImage.documentRows(count: 150))))
        let b = try XCTUnwrap(ImageStitcher.signature(of: TestImage.rows(width: width, colors: TestImage.documentRows(count: 150, start: 900))))
        XCTAssertNil(ImageStitcher.findMatch(previous: a, next: b))
    }
}
