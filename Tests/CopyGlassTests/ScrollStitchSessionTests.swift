import XCTest
import CoreGraphics
import AppKit
@testable import CopyGlass

final class ScrollStitchSessionTests: XCTestCase {
    private let width = 40
    private let frameHeight = 120

    // MARK: - Helpers

    private func makeDocument(count: Int = 600) -> CGImage {
        TestImage.rows(width: width, colors: TestImage.documentRows(count: count))
    }

    /// Pseudo-random row luminances: different rows never look alike. The colour-wheel document
    /// used for alignment tests aliases in luminance, so unrelated frames can line up by
    /// coincidence there; the "scrolled too fast" cases need an unambiguous document instead.
    private func makeNoiseDocument(count: Int = 600) -> CGImage {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var colors: [NSColor] = []
        colors.reserveCapacity(count)
        for _ in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let value = CGFloat((state >> 33) & 0xFF) / 255.0
            colors.append(NSColor(srgbRed: value, green: value, blue: value, alpha: 1))
        }
        return TestImage.rows(width: width, colors: colors)
    }

    private func frame(_ document: CGImage, top: Int) -> CGImage {
        ImageUtils.crop(
            document,
            topLeftRect: CGRect(x: 0, y: CGFloat(top), width: CGFloat(width), height: CGFloat(frameHeight))
        )!
    }

    private func assertRow(_ image: CGImage, _ row: Int, documentRow: Int, file: StaticString = #filePath, line: UInt = #line) {
        let expected = TestImage.colorComponents(TestImage.documentColor(row: documentRow))
        let actual = TestImage.pixel(image, x: 7, y: row)
        XCTAssertTrue(TestImage.isClose(actual, expected), "row \(row) should be document row \(documentRow)", file: file, line: line)
    }

    // MARK: - Shift estimation

    func testEstimateShiftDetectsBothScrollDirections() throws {
        let document = makeDocument()

        func signature(top: Int) throws -> ImageRowSignature {
            let crop = try XCTUnwrap(frame(document, top: top) as CGImage?)
            return try XCTUnwrap(ImageStitcher.signature(of: crop))
        }

        let scrolledDown = try XCTUnwrap(
            ImageStitcher.estimateShift(previous: try signature(top: 100), next: try signature(top: 140))
        )
        XCTAssertEqual(scrolledDown.rows, 40, "content moving up means the user scrolled down")

        let scrolledUp = try XCTUnwrap(
            ImageStitcher.estimateShift(previous: try signature(top: 140), next: try signature(top: 100))
        )
        XCTAssertEqual(scrolledUp.rows, -40, "content moving down means the user scrolled up")
    }

    func testEstimateShiftRejectsFramesWithoutOverlap() throws {
        let document = makeNoiseDocument()
        let previous = try XCTUnwrap(ImageStitcher.signature(of: frame(document, top: 0)))
        let next = try XCTUnwrap(ImageStitcher.signature(of: frame(document, top: 400)))
        XCTAssertNil(ImageStitcher.estimateShift(previous: previous, next: next))
    }

    // MARK: - Session

    func testScrollingUpExtendsTheDocumentUpward() throws {
        let document = makeDocument()
        let session = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(document, top: 240)))
        XCTAssertEqual(session.stitchedHeight, frameHeight)

        // The user scrolls up: each frame shows content 20 rows above the previous viewport.
        for top in stride(from: 220, through: 140, by: -20) {
            XCTAssertEqual(session.ingest(frame(document, top: top)), .extended(rows: 20), "frame at \(top)")
        }

        XCTAssertEqual(session.stitchedHeight, frameHeight + 100)
        XCTAssertEqual(session.capturedFrames, 6)

        let image = try XCTUnwrap(session.finalImage())
        XCTAssertEqual(image.height, frameHeight + 100)
        for row in [0, 50, frameHeight + 99] {
            assertRow(image, row, documentRow: 140 + row)
        }
    }

    func testScrollingDownExtendsTheDocumentDownward() throws {
        let document = makeDocument()
        let session = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(document, top: 100)))

        for top in stride(from: 120, through: 200, by: 20) {
            XCTAssertEqual(session.ingest(frame(document, top: top)), .extended(rows: 20), "frame at \(top)")
        }

        XCTAssertEqual(session.stitchedHeight, frameHeight + 100)
        let image = try XCTUnwrap(session.finalImage())
        for row in [0, 60, frameHeight + 99] {
            assertRow(image, row, documentRow: 100 + row)
        }
    }

    func testIdenticalFramesAreIgnored() throws {
        let document = makeDocument()
        let first = frame(document, top: 240)
        let session = try XCTUnwrap(ScrollStitchSession(firstFrame: first))
        XCTAssertEqual(session.ingest(frame(document, top: 240)), .unchanged)
        XCTAssertEqual(session.ingest(frame(document, top: 240)), .unchanged)
        XCTAssertEqual(session.stitchedHeight, frameHeight)
        XCTAssertEqual(session.appendedRows, 0)
    }

    func testTooFastScrollIsRejectedAndRecovers() throws {
        let document = makeNoiseDocument()
        let session = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(document, top: 240)))

        // Jumping further than the matcher can align must not corrupt the result.
        XCTAssertEqual(session.ingest(frame(document, top: 420)), .noMatch)
        XCTAssertEqual(session.stitchedHeight, frameHeight)

        // Scrolling back into the captured range continues from the last accepted frame.
        XCTAssertEqual(session.ingest(frame(document, top: 260)), .extended(rows: 20))
        XCTAssertEqual(session.stitchedHeight, frameHeight + 20)
    }

    func testScrollingBackAndForthDoesNotDuplicateRows() throws {
        let document = makeDocument()
        let session = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(document, top: 240)))

        for top in [220, 200, 180] {
            XCTAssertEqual(session.ingest(frame(document, top: top)), .extended(rows: 20))
        }
        XCTAssertEqual(session.stitchedHeight, frameHeight + 60)

        // Back to where the capture started (and a little below it): rows already captured are not
        // appended again.
        for top in [200, 220, 240] {
            XCTAssertEqual(session.ingest(frame(document, top: top)), .unchanged, "frame at \(top)")
        }
        XCTAssertEqual(session.stitchedHeight, frameHeight + 60)

        // Scrolling below the original viewport extends the bottom edge.
        XCTAssertEqual(session.ingest(frame(document, top: 260)), .extended(rows: 20))
        XCTAssertEqual(session.stitchedHeight, frameHeight + 80)

        let image = try XCTUnwrap(session.finalImage())
        XCTAssertEqual(image.height, frameHeight + 80)
        assertRow(image, 0, documentRow: 180)
        assertRow(image, frameHeight + 79, documentRow: 379)
    }

    func testHeightLimitStopsExtension() throws {
        let document = makeDocument()
        let session = try XCTUnwrap(
            ScrollStitchSession(firstFrame: frame(document, top: 240), maxHeight: frameHeight + 40)
        )
        XCTAssertEqual(session.ingest(frame(document, top: 220)), .extended(rows: 20))
        XCTAssertEqual(session.ingest(frame(document, top: 200)), .extended(rows: 20))
        XCTAssertEqual(session.stitchedHeight, frameHeight + 40)

        XCTAssertEqual(session.ingest(frame(document, top: 180)), .limitReached)
        XCTAssertTrue(session.reachedLimit)
        XCTAssertEqual(session.stitchedHeight, frameHeight + 40)

        // Once the limit is hit the session keeps reporting it instead of silently growing.
        XCTAssertEqual(session.ingest(frame(document, top: 160)), .limitReached)
        let image = try XCTUnwrap(session.finalImage())
        XCTAssertEqual(image.height, frameHeight + 40)
    }

    func testFramesWithUnexpectedSizeFail() throws {
        let document = makeDocument()
        let session = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(document, top: 240)))
        let wrong = ImageUtils.crop(
            document,
            topLeftRect: CGRect(x: 0, y: 100, width: CGFloat(width), height: CGFloat(frameHeight - 20))
        )!
        XCTAssertEqual(session.ingest(wrong), .failed)
        XCTAssertEqual(session.stitchedHeight, frameHeight)
    }
}
