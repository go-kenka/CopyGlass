import XCTest
import CoreGraphics
import AppKit
@testable import CopyGlass

/// Regression tests for scrolling-capture duplication.
///
/// A real window mixes scrolling content with fixed chrome. The stitcher must not repeat that
/// chrome (a sidebar, a sticky header, a bottom composer) and must not duplicate list rows when the
/// content is repetitive. These tests model such a window and assert both properties.
final class ScrollCaptureDeduplicationTests: XCTestCase {
    private let frameWidth: CGFloat = 600
    private let frameHeight: CGFloat = 600
    private let sidebarWidth: CGFloat = 200
    private let itemHeight: CGFloat = 20
    private let documentHeight = 4000
    private let initialOffset = 1200
    private let scrollStep = 80

    private let headerHeight: CGFloat = 40
    private let composerHeight: CGFloat = 80
    private let composerMarker = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
    private let headerColor = NSColor(srgbRed: 0.05, green: 0.2, blue: 0.6, alpha: 1)

    // MARK: - Synthetic window

    private func makeSidebar() -> CGImage {
        let context = ImageUtils.makeContext(width: Int(sidebarWidth), height: Int(frameHeight))!
        context.setFillColor(NSColor(calibratedWhite: 0.92, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: sidebarWidth, height: frameHeight))
        let styles: [(CGFloat, CGFloat)] = [(0.2, 120), (0.55, 90), (0.8, 150)]
        for row in 0..<(Int(frameHeight) / 40) {
            let y = frameHeight - CGFloat(row + 1) * 40
            let (tint, bar) = styles[row % styles.count]
            context.setFillColor(NSColor(srgbRed: tint, green: 0.6, blue: 1 - tint, alpha: 1).cgColor)
            context.fill(CGRect(x: 16, y: y + 12, width: 16, height: 16))
            context.setFillColor(NSColor(calibratedWhite: 0.3, alpha: 1).cgColor)
            context.fill(CGRect(x: 44, y: y + 18, width: bar, height: 5))
        }
        return context.makeImage()!
    }

    private func makeScrollingDocument() -> CGImage {
        let width = Int(frameWidth - sidebarWidth)
        let context = ImageUtils.makeContext(width: width, height: documentHeight)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: documentHeight))
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        for item in 0..<(documentHeight / Int(itemHeight)) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let red = CGFloat((state >> 33) & 0xFF) / 255
            let green = CGFloat((state >> 41) & 0xFF) / 255
            let blue = CGFloat((state >> 49) & 0xFF) / 255
            let y = CGFloat(documentHeight) - CGFloat(item) * itemHeight - itemHeight
            let iconOffset = CGFloat((state >> 11) % 7)
            context.setFillColor(NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).cgColor)
            context.fill(CGRect(x: 12, y: y + iconOffset, width: 14, height: 12))
            let barWidth = 60 + CGFloat((state >> 20) & 0x7F)
            let barOffset = CGFloat((state >> 15) % 9)
            let barHeight = 2 + CGFloat((state >> 17) % 4)
            context.setFillColor(NSColor(calibratedWhite: 0.25, alpha: 1).cgColor)
            context.fill(CGRect(x: 40, y: y + barOffset, width: barWidth, height: barHeight))
            if state % 2 == 0 {
                let secondOffset = CGFloat((state >> 25) % 5)
                context.fill(CGRect(x: 40, y: y + 13 + secondOffset * 0.6, width: barWidth * 0.6, height: 2))
            }
        }
        return context.makeImage()!
    }

    private func makeFrame(
        document: CGImage,
        sidebar: CGImage,
        offset: Int,
        withChrome: Bool = false
    ) -> CGImage {
        let context = ImageUtils.makeContext(width: Int(frameWidth), height: Int(frameHeight))!
        context.interpolationQuality = .none
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight))
        context.draw(sidebar, in: CGRect(x: 0, y: 0, width: sidebarWidth, height: frameHeight))
        let crop = ImageUtils.crop(
            document,
            topLeftRect: CGRect(
                x: 0,
                y: CGFloat(offset),
                width: frameWidth - sidebarWidth,
                height: frameHeight - (withChrome ? headerHeight + composerHeight : 0)
            )
        )!
        let contentRect = withChrome
            ? CGRect(x: sidebarWidth, y: composerHeight, width: frameWidth - sidebarWidth, height: frameHeight - headerHeight - composerHeight)
            : CGRect(x: sidebarWidth, y: 0, width: frameWidth - sidebarWidth, height: frameHeight)
        context.draw(crop, in: contentRect)

        if withChrome {
            // Sticky header and a fixed bottom composer, identical in every frame.
            context.setFillColor(headerColor.cgColor)
            context.fill(CGRect(x: 0, y: frameHeight - headerHeight, width: frameWidth, height: headerHeight))
            context.setFillColor(NSColor(calibratedWhite: 0.88, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: frameWidth, height: composerHeight))
            context.setFillColor(composerMarker.cgColor)
            context.fill(CGRect(x: 285, y: 20, width: 40, height: 40))
        }
        return context.makeImage()!
    }

    // MARK: - Tests

    func testFixedSidebarIsNotRepeatedAndListHasNoDuplicates() throws {
        let document = makeScrollingDocument()
        let sidebar = makeSidebar()
        let session = try XCTUnwrap(
            ScrollStitchSession(firstFrame: makeFrame(document: document, sidebar: sidebar, offset: initialOffset))
        )

        var offset = initialOffset
        for _ in 0..<9 {
            offset -= scrollStep
            let outcome = session.ingest(makeFrame(document: document, sidebar: sidebar, offset: offset))
            XCTAssertEqual(outcome, .extended(rows: scrollStep), "frame at offset \(offset)")
        }

        let expectedHeight = Int(frameHeight) + 9 * scrollStep
        XCTAssertEqual(session.stitchedHeight, expectedHeight)
        let image = try XCTUnwrap(session.finalImage())
        XCTAssertEqual(image.height, expectedHeight)

        // Cells are classified: the sidebar block is fixed, the list is moving.
        let cells = session.resolvedStaticCells()
        XCTAssertEqual(session.cellColumns, ScrollStitchSession.signatureWidth)
        XCTAssertEqual(cells.count, session.cellRows * ScrollStitchSession.signatureWidth)
        XCTAssertTrue(cells[5 * session.cellColumns + 10], "sidebar cells must be classified as fixed")
        XCTAssertFalse(cells[5 * session.cellColumns + 48], "list cells must be classified as moving")

        // Scrolling content lines up with the source document, with no duplicated/missing rows.
        let finalViewportOffset = initialOffset - 9 * scrollStep
        for y in [0, 100, 400, 700, 719, 720, 1000, 1319] {
            let documentRow = finalViewportOffset + y
            for x in [218, 245] {
                let actual = TestImage.pixel(image, x: x, y: y)
                let expected = TestImage.pixel(document, x: x - Int(sidebarWidth), y: documentRow)
                XCTAssertTrue(
                    TestImage.isClose(actual, expected, tolerance: 8),
                    "row \(y) x \(x) should show document row \(documentRow), got \(actual) vs \(expected)"
                )
            }
        }

        // The sidebar is drawn once from the first frame; the extension uses the background
        // colour instead of repeating the icon list.
        for x in [20, 60, 180] {
            let firstExtendedRow = TestImage.pixel(image, x: x, y: 0)
            for y in [100, 300, 500, 719] {
                let actual = TestImage.pixel(image, x: x, y: y)
                XCTAssertTrue(
                    TestImage.isClose(actual, firstExtendedRow, tolerance: 8),
                    "sidebar x \(x) row \(y) must be the background continuation, not repeated icons"
                )
            }
        }
    }

    func testFixedBottomComposerIsNotRepeated() throws {
        let document = makeScrollingDocument()
        let sidebar = makeSidebar()
        let session = try XCTUnwrap(
            ScrollStitchSession(firstFrame: makeFrame(document: document, sidebar: sidebar, offset: 2000, withChrome: true))
        )

        var offset = 2000
        for _ in 0..<8 {
            offset += scrollStep
            let outcome = session.ingest(makeFrame(document: document, sidebar: sidebar, offset: offset, withChrome: true))
            XCTAssertEqual(outcome, .extended(rows: scrollStep), "frame at offset \(offset)")
        }

        let image = try XCTUnwrap(session.finalImage())
        let expectedHeight = Int(frameHeight) + 8 * scrollStep
        XCTAssertEqual(image.height, expectedHeight)

        let marker = TestImage.colorComponents(composerMarker)
        // The fixed composer must never be repeated: scrolling content takes its place in the long
        // image (the composer itself is not part of the scrolling document).
        for y in [560, 620, 700, 820, 940, 1060, 1200] {
            let repeated = TestImage.pixel(image, x: 300, y: y)
            XCTAssertFalse(
                TestImage.isClose(repeated, marker, tolerance: 10),
                "the composer must not be repeated at row \(y)"
            )
        }
        // The sticky header is painted once at the top and never repeated either.
        let header = TestImage.colorComponents(headerColor)
        XCTAssertTrue(
            TestImage.isClose(TestImage.pixel(image, x: 300, y: 10), header, tolerance: 10),
            "the sticky header must be visible once at the top"
        )
        for y in [700, 900, 1100] {
            XCTAssertFalse(
                TestImage.isClose(TestImage.pixel(image, x: 300, y: y), header, tolerance: 10),
                "the sticky header must not be repeated at row \(y)"
            )
        }

        // The scrolling list still lines up inside the visible content band (the band starts
        // `headerHeight` rows below the frame top, so image row y shows document row
        // (2000 + y - headerHeight)).
        for y in [100, 300, 500, 700, 900, 1100] {
            let documentRow = 2000 + y - Int(headerHeight)
            let actual = TestImage.pixel(image, x: 245, y: y)
            let expected = TestImage.pixel(document, x: 245 - Int(sidebarWidth), y: documentRow)
            XCTAssertTrue(
                TestImage.isClose(actual, expected, tolerance: 8),
                "row \(y) should show document row \(documentRow)"
            )
        }

        // Fixed cells are fixed, the list cells moved.
        let cells = session.resolvedStaticCells()
        XCTAssertTrue(cells[(session.cellRows - 1) * session.cellColumns + 50], "the composer row must be fixed")
        XCTAssertFalse(cells[5 * session.cellColumns + 48], "the list rows must be moving")
    }

    func testSmallStepsStillAlign() throws {
        let document = makeScrollingDocument()
        let sidebar = makeSidebar()
        let session = try XCTUnwrap(
            ScrollStitchSession(firstFrame: makeFrame(document: document, sidebar: sidebar, offset: 2000))
        )
        var offset = 2000
        for _ in 0..<12 {
            offset -= 40
            _ = session.ingest(makeFrame(document: document, sidebar: sidebar, offset: offset))
        }
        XCTAssertEqual(session.stitchedHeight, Int(frameHeight) + 12 * 40)

        let image = try XCTUnwrap(session.finalImage())
        let finalViewportOffset = 2000 - 12 * 40
        for y in stride(from: 0, to: image.height, by: 97) {
            let documentRow = finalViewportOffset + y
            let actual = TestImage.pixel(image, x: 245, y: y)
            let expected = TestImage.pixel(document, x: 245 - Int(sidebarWidth), y: documentRow)
            XCTAssertTrue(
                TestImage.isClose(actual, expected, tolerance: 8),
                "row \(y) should show document row \(documentRow)"
            )
        }
    }
}
