import XCTest
import CoreGraphics
import AppKit
@testable import CopyGlass

/// Helpers for building deterministic synthetic images for the screenshot pipeline tests.
enum TestImage {
    /// Every document row gets a unique color so row alignment is unambiguous.
    static func documentColor(row: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((row * 37 + 11) % 251) / 251.0,
            green: CGFloat((row * 91 + 29) % 241) / 241.0,
            blue: CGFloat((row * 53 + 7) % 239) / 239.0,
            alpha: 1.0
        )
    }

    static func solid(_ color: NSColor, width: Int, height: Int) -> CGImage {
        let context = ImageUtils.makeContext(width: width, height: height)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Fills rows with a supplied per-row color; row 0 is the top row of the resulting image.
    static func rows(width: Int, colors: [NSColor]) -> CGImage {
        let height = colors.count
        let context = ImageUtils.makeContext(width: width, height: height)!
        for (row, color) in colors.enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: height - row - 1, width: width, height: 1))
        }
        return context.makeImage()!
    }

    static func documentRows(count: Int, start: Int = 0) -> [NSColor] {
        (0..<count).map { documentColor(row: start + $0) }
    }

    /// Reads a pixel using top-left origin coordinates.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let context = ImageUtils.makeContext(width: 1, height: 1)!
        let offsetY = CGFloat(-(image.height - y - 1))
        context.draw(image, in: CGRect(x: CGFloat(-x), y: offsetY, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let raw = context.data else { return (0, 0, 0) }
        let buffer = raw.bindMemory(to: UInt8.self, capacity: 4)
        return (Int(buffer[2]), Int(buffer[1]), Int(buffer[0]))
    }

    static func colorComponents(_ color: NSColor) -> (r: Int, g: Int, b: Int) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        return (
            Int((converted.redComponent * 255).rounded()),
            Int((converted.greenComponent * 255).rounded()),
            Int((converted.blueComponent * 255).rounded())
        )
    }

    static func isClose(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int), tolerance: Int = 6) -> Bool {
        abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
    }

    /// Number of pixels in a rect that differ from the supplied color.
    static func differingPixels(_ image: CGImage, in rect: CGRect, from color: NSColor, tolerance: Int = 12) -> Int {
        var count = 0
        let expected = colorComponents(color)
        let minX = max(0, Int(rect.minX))
        let maxX = min(image.width - 1, Int(rect.maxX) - 1)
        let minY = max(0, Int(rect.minY))
        let maxY = min(image.height - 1, Int(rect.maxY) - 1)
        guard minX <= maxX, minY <= maxY else { return 0 }
        for y in minY...maxY {
            for x in minX...maxX {
                let value = pixel(image, x: x, y: y)
                if !isClose(value, expected, tolerance: tolerance) {
                    count += 1
                }
            }
        }
        return count
    }
}
