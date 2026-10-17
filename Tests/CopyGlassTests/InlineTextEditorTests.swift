import XCTest
import AppKit
@testable import CopyGlass

/// The inline text editor: transparent bordered box, centred text, width following the text.
final class InlineTextEditorTests: XCTestCase {
    private struct Rendered {
        let box: CGRect
        let ink: CGRect
        let interiorIsClear: Bool
    }

    private func render(_ editor: InlineTextEditor, canvas: CGSize = CGSize(width: 520, height: 200), baseline: CGFloat, x: CGFloat = 40, requireInk: Bool = true) throws -> Rendered {
        let host = NSView(frame: CGRect(origin: .zero, size: canvas))
        host.wantsLayer = true
        let backdrop = NSView(frame: CGRect(origin: .zero, size: canvas))
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.white.cgColor
        host.addSubview(backdrop)
        host.addSubview(editor)
        editor.place(baseline: baseline, x: x)

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / canvas.height

        var boxTop = Int.max, boxBottom = Int.min, boxLeft = Int.max, boxRight = Int.min
        var inkTop = Int.max, inkBottom = Int.min
        var greyInterior = 0
        for row in 0..<rep.pixelsHigh {
            for column in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: column, y: row), colour.alphaComponent > 0.4 else { continue }
                let isBorder = colour.blueComponent > 0.7 && colour.redComponent < 0.5
                if isBorder {
                    boxTop = min(boxTop, row); boxBottom = max(boxBottom, row)
                    boxLeft = min(boxLeft, column); boxRight = max(boxRight, column)
                } else if colour.brightnessComponent < 0.5 {
                    inkTop = min(inkTop, row); inkBottom = max(inkBottom, row)
                } else if colour.brightnessComponent < 0.9 {
                    greyInterior += 1
                }
            }
        }
        XCTAssertLessThan(boxTop, Int.max, "the border box should be drawn")
        if requireInk {
            XCTAssertLessThan(inkTop, Int.max, "the text should be drawn")
        } else {
            XCTAssertEqual(inkTop, Int.max, "nothing but the border may be painted")
        }

        let toView: (Int) -> CGFloat = { CGFloat($0) / scale }
        // Bitmap rows are top-down; convert to view (bottom-up) coordinates.
        let boxRect = CGRect(
            x: toView(boxLeft),
            y: canvas.height - toView(boxBottom),
            width: toView(boxRight - boxLeft),
            height: toView(boxBottom - boxTop)
        )
        let inkRect: CGRect
        if inkTop <= inkBottom {
            inkRect = CGRect(
                x: 0,
                y: canvas.height - toView(inkBottom),
                width: 0,
                height: toView(inkBottom - inkTop)
            )
        } else {
            inkRect = .null
        }
        return Rendered(box: boxRect, ink: inkRect, interiorIsClear: greyInterior == 0)
    }

    func testTextIsVerticallyCentredInTheBox() throws {
        for fontSize in [16.0, 24.0, 32.0, 48.0] {
            let editor = InlineTextEditor(text: "CopyGlass", fontSize: CGFloat(fontSize), textColor: .black)
            let rendered = try render(editor, baseline: 80)
            let slackTop = rendered.ink.maxY - rendered.box.maxY
            let slackBottom = rendered.box.minY - rendered.ink.minY
            XCTAssertEqual(
                slackTop, slackBottom, accuracy: 1.5,
                "font \(fontSize): text should be centred (top slack \(slackTop), bottom slack \(slackBottom))"
            )
        }
    }

    func testTextBaselineLandsOnTheRequestedPosition() throws {
        let fontSize: CGFloat = 32
        let editor = InlineTextEditor(text: "CopyGlass", fontSize: fontSize, textColor: .black)
        let baseline: CGFloat = 80
        let rendered = try render(editor, baseline: baseline, x: 40)

        // The ink bottom is the descender; the baseline sits that far above it.
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let measuredBaseline = rendered.ink.minY + abs(font.descender)
        XCTAssertEqual(measuredBaseline, baseline, accuracy: 1.5, "the editor must show the text where it will be drawn")
        XCTAssertEqual(rendered.box.minX + 7, 40, accuracy: 2, "the box starts at the annotation origin")
    }

    func testBoxBackgroundIsTransparentAndWidthFollowsTheText() throws {
        // An empty annotation paints nothing but its border, which proves the box has no fill.
        let emptyBox = InlineTextEditor(text: "", fontSize: 24, textColor: .black)
        let emptyBoxRender = try render(emptyBox, baseline: 80, requireInk: false)
        XCTAssertTrue(emptyBoxRender.interiorIsClear, "the box must not paint a grey background")

        let short = InlineTextEditor(text: "Hi", fontSize: 24, textColor: .black)
        let shortRender = try render(short, baseline: 80)
        XCTAssertEqual(shortRender.interiorIsClear, false, "the text itself is of course drawn")

        let long = InlineTextEditor(text: "CopyGlass is a clipboard manager", fontSize: 24, textColor: .black)
        let longRender = try render(long, baseline: 80)
        XCTAssertGreaterThan(longRender.box.width, shortRender.box.width + 100, "the box grows with the text")
        XCTAssertEqual(longRender.box.height, shortRender.box.height, accuracy: 1, "height depends on the font only")

        // An empty annotation still shows a box big enough to type into.
        let empty = InlineTextEditor(text: "", fontSize: 24, textColor: .black)
        let emptyRender = try render(empty, baseline: 80, requireInk: false)
        XCTAssertGreaterThan(emptyRender.box.width, 30)
    }

    func testEmptyTextProducesNoInk() throws {
        let editor = InlineTextEditor(text: "", fontSize: 24, textColor: .black)
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 120))
        host.wantsLayer = true
        let backdrop = NSView(frame: host.bounds)
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.white.cgColor
        host.addSubview(backdrop)
        host.addSubview(editor)
        editor.place(baseline: 60, x: 40)
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        var darkPixels = 0
        for row in 0..<rep.pixelsHigh {
            for column in 0..<rep.pixelsWide {
                if let colour = rep.colorAt(x: column, y: row),
                   colour.alphaComponent > 0.4,
                   colour.brightnessComponent < 0.5,
                   !(colour.blueComponent > 0.7 && colour.redComponent < 0.5) {
                    darkPixels += 1
                }
            }
        }
        XCTAssertEqual(darkPixels, 0, "nothing should be drawn for empty text")
    }
}
