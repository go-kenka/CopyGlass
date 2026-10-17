import XCTest
import AppKit
@testable import CopyGlass

/// TEMPORARY: measures the top inset NSTextField applies, across font sizes.
final class TextFieldAlignmentProbeTests: XCTestCase {
    private func measure(fontSize: CGFloat, fieldHeight: CGFloat) -> (glyphTop: CGFloat, glyphBottom: CGFloat, ascender: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 260, height: fieldHeight))
        field.font = font
        field.stringValue = "CopyGlass"
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = false
        field.isSelectable = false

        let host = NSView(frame: CGRect(x: 0, y: 0, width: 260, height: fieldHeight))
        host.addSubview(field)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return (-1, -1, font.ascender) }
        host.cacheDisplay(in: host.bounds, to: rep)

        let scale = CGFloat(rep.pixelsHigh) / fieldHeight
        var top = Int.max, bottom = Int.min
        for row in 0..<rep.pixelsHigh {
            for column in 0..<rep.pixelsWide {
                if let colour = rep.colorAt(x: column, y: row), colour.alphaComponent > 0.35,
                   colour.brightnessComponent < 0.6 {
                    top = min(top, row); bottom = max(bottom, row)
                }
            }
        }
        guard top <= bottom else { return (-1, -1, font.ascender) }
        return (CGFloat(top) / scale, CGFloat(bottom) / scale, font.ascender)
    }

    func testProbeInsetsAcrossFontSizes() throws {
        for fontSize in [12.0, 16.0, 24.0, 36.0, 48.0] {
            let result = measure(fontSize: fontSize, fieldHeight: 80)
            let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            print(String(format: "font %4.0f: ascender=%6.2f lineHeight=%6.2f | glyphTop=%6.2f glyphBottom=%6.2f | insetTop=%6.2f",
                         fontSize, font.ascender, font.ascender - font.descender,
                         result.glyphTop, result.glyphBottom, result.glyphTop))
        }
    }
}
