import XCTest
import SwiftUI
import AppKit
@testable import CopyGlass

/// Verifies the overlay drawing math and that the floating toolbar can actually be hosted.
final class OverlayRenderingTests: XCTestCase {
    /// Mirrors what SelectionOverlayView does in the editing phase: the crop is mapped onto the
    /// selection rectangle and clipped to it.
    func testAnnotationLandsWhereTheUserDrewIt() throws {
        // A 600x400 frozen screen with a 200x120 capture placed at (100, 80) — 1:1 like a
        // non-Retina crop.
        let crop = TestImage.solid(.white, width: 200, height: 120)
        let session = CaptureSession(image: crop)
        let transform = CanvasTransform(
            scale: 1,
            origin: CGPoint(x: 100, y: 80),
            imageSize: CGSize(width: 200, height: 120)
        )
        // Red rectangle around image rect (10,10)-(30,30).
        session.commit(AnnotationShape.rectangle(
            from: CGPoint(x: 10, y: 10),
            to: CGPoint(x: 30, y: 30),
            color: AnnotationColor(red: 1, green: 0, blue: 0),
            lineWidth: 4
        ))

        let context = try XCTUnwrap(ImageUtils.makeContext(width: 600, height: 400))
        context.clip(to: CGRect(x: 100, y: 80, width: 200, height: 120))
        AnnotationRenderer.draw(base: crop, shapes: session.shapes, in: context, transform: transform)
        let rendered = try XCTUnwrap(context.makeImage())

        // image (x, y) -> view (100 + x, 200 - y); bitmap row = 400 - viewY - 1.
        // Left edge of the rectangle: image (10, 20) -> view (110, 180) -> row 219.
        let onEdge = TestImage.pixel(rendered, x: 110, y: 219)
        XCTAssertTrue(TestImage.isClose(onEdge, (255, 0, 0), tolerance: 40), "expected the red stroke, got \(onEdge)")

        // Untouched capture pixels: image (75, 70) -> view (175, 130) -> row 269.
        let insideCrop = TestImage.pixel(rendered, x: 175, y: 269)
        XCTAssertTrue(TestImage.isClose(insideCrop, (255, 255, 255), tolerance: 6), "expected the capture pixels, got \(insideCrop)")

        // Outside the selection the canvas stays transparent: nothing is drawn there.
        let outside = TestImage.pixel(rendered, x: 500, y: 379)
        XCTAssertTrue(TestImage.isClose(outside, (0, 0, 0), tolerance: 2), "nothing should be drawn outside the selection")
    }

    /// The step-number badge must have its digit centred on the circle.
    func testNumberBadgeDigitIsCentred() throws {
        let base = TestImage.solid(.white, width: 200, height: 200)
        let centre = CGPoint(x: 100, y: 100)
        let lineWidth: CGFloat = 4
        let radius = max(14, lineWidth * 5)

        for label in [1, 8, 12] {
            let shape = AnnotationShape(
                tool: .number,
                points: [centre],
                color: AnnotationColor(red: 1, green: 0, blue: 0),
                lineWidth: lineWidth,
                label: label
            )
            let rendered = try XCTUnwrap(AnnotationRenderer.render(base: base, shapes: [shape]))

            var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
            for y in Int(centre.y - radius + 2)...Int(centre.y + radius - 2) {
                for x in Int(centre.x - radius + 2)...Int(centre.x + radius - 2) {
                    let distance = hypot(Double(x) - Double(centre.x), Double(y) - Double(centre.y))
                    guard distance <= Double(radius) - 2 else { continue }
                    let pixel = TestImage.pixel(rendered, x: x, y: y)
                    if pixel.r > 200, pixel.g > 200, pixel.b > 200 {
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            XCTAssertLessThan(minX, maxX, "badge \(label) should contain the white digit")
            XCTAssertEqual(Double(minX + maxX) / 2, Double(centre.x), accuracy: 2.5, "digit \(label) is not horizontally centred")
            XCTAssertEqual(Double(minY + maxY) / 2, Double(centre.y), accuracy: 2.5, "digit \(label) is not vertically centred")
        }
    }

    /// The cursor marker is a small crosshair with a clear centre, not full-screen guides.
    func testCursorCrosshairIsSmallAndHasACentreGap() throws {
        let context = try XCTUnwrap(ImageUtils.makeContext(width: 100, height: 100))
        AnnotationRenderer.drawCursorCrosshair(at: CGPoint(x: 50, y: 50), in: context, arm: 9, gap: 3, scale: 1)
        let image = try XCTUnwrap(context.makeImage())

        // View point (x, y) -> bitmap row (100 - y - 1).
        func pixel(viewX: Int, viewY: Int) -> (r: Int, g: Int, b: Int) {
            TestImage.pixel(image, x: viewX, y: 100 - viewY - 1)
        }

        XCTAssertGreaterThan(pixel(viewX: 55, viewY: 50).r, 180, "right arm should be drawn")
        XCTAssertGreaterThan(pixel(viewX: 50, viewY: 55).r, 180, "top arm should be drawn")
        XCTAssertLessThan(pixel(viewX: 50, viewY: 50).r, 130, "the centre pixel should stay visible")
        XCTAssertLessThan(pixel(viewX: 80, viewY: 50).r, 60, "there must be no full-screen guide line")
        XCTAssertLessThan(pixel(viewX: 50, viewY: 20).r, 60, "there must be no full-screen guide line")
    }

    // MARK: - Selection phase composition (window-first capture)

    private func renderSelectionPhase(
        dragged: CGRect? = nil,
        hovered: CGRect? = nil,
        size: CGSize = CGSize(width: 400, height: 300)
    ) throws -> CGImage {
        let frozen = TestImage.solid(.white, width: Int(size.width), height: Int(size.height))
        let context = try XCTUnwrap(ImageUtils.makeContext(width: Int(size.width), height: Int(size.height)))
        SelectionPhaseRenderer.draw(
            SelectionPhaseRenderer.State(
                bounds: CGRect(origin: .zero, size: size),
                frozenImage: frozen,
                draggedSelection: dragged,
                hoveredWindow: hovered
            ),
            in: context
        )
        return try XCTUnwrap(context.makeImage())
    }

    /// View point (x, y) -> bitmap row (height - y - 1).
    private func viewPixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        TestImage.pixel(image, x: x, y: image.height - y - 1)
    }

    /// The window under the pointer must stay bright; only the rest of the screen is dimmed.
    func testHoveredWindowStaysBrightAndIsOutlined() throws {
        let hovered = CGRect(x: 100, y: 100, width: 200, height: 120)
        let image = try renderSelectionPhase(hovered: hovered)

        let inside = viewPixel(image, x: 200, y: 160)
        XCTAssertTrue(TestImage.isClose(inside, (255, 255, 255), tolerance: 6), "the hovered window must not be dimmed, got \(inside)")

        let outside = viewPixel(image, x: 20, y: 20)
        XCTAssertLessThan(outside.r, 200, "the desktop outside the window must be dimmed, got \(outside)")

        let border = viewPixel(image, x: 100, y: 160)
        XCTAssertGreaterThan(border.b, border.r + 40, "the hovered window should be outlined, got \(border)")
    }

    /// With nothing hovered and nothing dragged the whole screen is dimmed.
    func testNothingSelectedDimsTheWholeScreen() throws {
        let image = try renderSelectionPhase()
        let corner = viewPixel(image, x: 20, y: 20)
        XCTAssertLessThan(corner.r, 200)
        let middle = viewPixel(image, x: 200, y: 150)
        XCTAssertLessThan(middle.r, 200)
    }

    /// A dragged region wins over the hovered window and keeps its handles.
    func testDraggedRegionStaysBrightInsteadOfTheHoveredWindow() throws {
        let dragged = CGRect(x: 40, y: 40, width: 120, height: 80)
        let hovered = CGRect(x: 220, y: 140, width: 150, height: 120)
        let image = try renderSelectionPhase(dragged: dragged, hovered: hovered)

        let insideDrag = viewPixel(image, x: 80, y: 80)
        XCTAssertTrue(TestImage.isClose(insideDrag, (255, 255, 255), tolerance: 6), "the dragged region must stay bright")

        let insideHover = viewPixel(image, x: 290, y: 200)
        XCTAssertLessThan(insideHover.r, 200, "the hovered window must not stay bright while dragging")
    }

    /// The toolbar is hosted in a bare NSHostingView over the frozen screen, where an
    /// environment-provided language would silently fall back to English; the language is therefore
    /// a required parameter and must drive the strings.
    func testToolbarUsesTheLanguageItIsGiven() {
        for language in AppLanguage.allCases {
            for key in [L10nKey.ocrTitle, .copyAll, .noTextFound, .undo, .pin, .save, .copy, .cancel] {
                XCTAssertFalse(L10n.t(key, lang: language).isEmpty)
            }
        }
        XCTAssertNotEqual(L10n.t(.ocrTitle, lang: .zhHans), L10n.t(.ocrTitle, lang: .en))
    }

    func testToolbarAndOCRPanelLayOut() {
        let session = CaptureSession(image: TestImage.solid(.white, width: 200, height: 120))
        let host = NSHostingView(rootView: ScreenshotToolbarContainer(
            session: session,
            language: .zhHans,
            onCopy: {},
            onSave: {},
            onPin: {},
            onExtractText: {},
            onCopyText: { _ in },
            onCancel: {}
        ))
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 200)
        host.layoutSubtreeIfNeeded()
        let toolSize = host.fittingSize
        XCTAssertGreaterThan(toolSize.width, 400, "the tool bar should fit every tool and action")
        XCTAssertGreaterThan(toolSize.height, 24)
        XCTAssertLessThan(toolSize.height, 80)

        session.panel = .ocr
        host.layoutSubtreeIfNeeded()
        let ocrSize = host.fittingSize
        XCTAssertEqual(ocrSize.width, 420, accuracy: 1)
        XCTAssertEqual(ocrSize.height, 320, accuracy: 1)
    }
}
