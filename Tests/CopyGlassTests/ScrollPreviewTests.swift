import XCTest
import AppKit
import CoreGraphics
@testable import CopyGlass

final class ScrollPreviewTests: XCTestCase {
    private func makeDocument(count: Int = 900) -> CGImage {
        TestImage.rows(width: 60, colors: TestImage.documentRows(count: count))
    }

    private func frame(_ document: CGImage, top: Int) -> CGImage {
        ImageUtils.crop(
            document,
            topLeftRect: CGRect(x: 0, y: CGFloat(top), width: 60, height: 120)
        )!
    }

    func testSnapshotFollowsTheGrowingDocument() throws {
        let document = makeDocument()
        let session = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(document, top: 240)))
        XCTAssertEqual(session.previewSnapshot.top, 0)
        XCTAssertEqual(session.previewSnapshot.bottom, 120)
        XCTAssertEqual(session.previewSnapshot.frames.count, 1)

        XCTAssertEqual(session.ingest(frame(document, top: 220)), .extended(rows: 20))
        let snapshot = session.previewSnapshot
        XCTAssertEqual(snapshot.top, -20)
        XCTAssertEqual(snapshot.bottom, 120)
        XCTAssertEqual(snapshot.frames.count, 2)
        XCTAssertEqual(snapshot.frameWidth, 60)
        XCTAssertEqual(snapshot.frameHeight, 120)
    }

    func testPreviewViewDrawsTheStitchedImage() throws {
        let document = makeDocument()
        let session = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(document, top: 400)))
        for top in stride(from: 380, through: 200, by: -20) {
            _ = session.ingest(frame(document, top: top))
        }
        let snapshot = session.previewSnapshot
        XCTAssertGreaterThan(snapshot.bottom - snapshot.top, 120)

        let view = ScrollPreviewView()
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 320)
        view.update(snapshot: snapshot)

        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        // The preview must actually paint the stitched rows, not just its background.
        var distinct = Set<String>()
        for y in stride(from: 20, to: 300, by: 25) {
            for x in stride(from: 20, to: 140, by: 30) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let key = String(format: "%.2f-%.2f-%.2f", color.redComponent, color.greenComponent, color.blueComponent)
                distinct.insert(key)
            }
        }
        XCTAssertGreaterThan(distinct.count, 3, "the preview should draw the stitched image rows")
    }

    func testPreviewUpdateIgnoresUnchangedSnapshots() throws {
        let document = makeDocument()
        let session = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(document, top: 240)))
        let view = ScrollPreviewView()
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 320)
        view.update(snapshot: session.previewSnapshot)
        // A repeated snapshot is a no-op (the view skips the redraw); this must not crash.
        view.update(snapshot: session.previewSnapshot)
        view.displayIfNeeded()
    }

    func testPreviewAnchorsToTheGrowingEnd() throws {
        let width = 400
        // Row-level texture (needed by the frame matcher) tinted blue for the top half and red for
        // the bottom half, so the anchoring assertions stay readable.
        func tint(_ base: NSColor, row: Int) -> NSColor {
            let sample = TestImage.documentColor(row: row).usingColorSpace(.sRGB) ?? .black
            let r = base.redComponent * 0.8 + sample.redComponent * 0.2
            let g = base.greenComponent * 0.8 + sample.greenComponent * 0.2
            let b = base.blueComponent * 0.8 + sample.blueComponent * 0.2
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
        let blue = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.9, alpha: 1)
        let red = NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        let colors = (0..<4000).map { tint($0 < 2000 ? blue : red, row: $0) }
        let document = TestImage.rows(width: width, colors: colors)
        func frame(_ top: Int) -> CGImage {
            ImageUtils.crop(document, topLeftRect: CGRect(x: 0, y: CGFloat(top), width: CGFloat(width), height: 300))!
        }
        let view = ScrollPreviewView()
        view.frame = CGRect(x: 0, y: 0, width: 176, height: 520)

        // Scrolling up prepends at the top: the newest rows stay at the top edge, the overgrown part
        // is clipped below.
        let upward = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(2500)))
        for top in stride(from: 2400, through: 0, by: -100) {
            _ = upward.ingest(frame(top))
        }
        view.update(snapshot: upward.previewSnapshot)
        let upwardLayout = try XCTUnwrap(view.layout(in: view.bounds))
        XCTAssertFalse(upwardLayout.growsAtBottom)
        XCTAssertGreaterThan(upwardLayout.totalHeight, view.bounds.height)
        XCTAssertEqual(upwardLayout.topY, view.bounds.insetBy(dx: 8, dy: 8).maxY, accuracy: 0.5)

        // Scrolling down appends at the bottom: the newest rows sit against the bottom edge.
        let downward = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(0)))
        for top in stride(from: 100, through: 3900, by: 100) {
            _ = downward.ingest(frame(top))
        }
        view.update(snapshot: downward.previewSnapshot)
        let downwardLayout = try XCTUnwrap(view.layout(in: view.bounds))
        XCTAssertTrue(downwardLayout.growsAtBottom)
        XCTAssertGreaterThan(downwardLayout.totalHeight, view.bounds.height)
        XCTAssertEqual(
            downwardLayout.topY,
            view.bounds.insetBy(dx: 8, dy: 8).minY + downwardLayout.totalHeight,
            accuracy: 0.5
        )

        // A short document is shown from the top while it is still being captured.
        let short = try XCTUnwrap(ScrollStitchSession(firstFrame: frame(100)))
        view.update(snapshot: short.previewSnapshot)
        let shortLayout = try XCTUnwrap(view.layout(in: view.bounds))
        XCTAssertLessThanOrEqual(shortLayout.totalHeight, view.bounds.height)
        XCTAssertEqual(shortLayout.topY, view.bounds.insetBy(dx: 8, dy: 8).maxY, accuracy: 0.5)
    }
}
