import Foundation
import CoreGraphics

/// A compact grayscale signature of an image: one row of sampled columns per image row.
/// Rows are stored top-down, matching the on-screen orientation.
struct ImageRowSignature: Equatable {
    let width: Int
    let height: Int
    let gray: [UInt8]

    static func == (lhs: ImageRowSignature, rhs: ImageRowSignature) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.gray == rhs.gray
    }
}

/// Alignment between the bottom of an accumulated image and the top of a freshly captured frame.
struct StitchMatch: Equatable {
    /// Row index in the previous image where the overlap starts.
    let previousStart: Int
    /// Row index in the next image where the overlap starts.
    let nextStart: Int
    /// Number of rows known to be shared by both images.
    let length: Int

    /// How many new rows the next frame contributes.
    func appendedRows(nextHeight: Int) -> Int {
        max(0, nextHeight - (nextStart + length))
    }
}

/// Row-signature based vertical stitcher used by the scrolling screenshot feature.
enum ImageStitcher {
    static let defaultSampleWidth = 48
    static let defaultTolerance = 6.0
    static let identicalTolerance = 1.5

    /// Downsamples an image to a grayscale row signature (height preserved, width reduced).
    static func signature(of image: CGImage, sampleWidth: Int = defaultSampleWidth) -> ImageRowSignature? {
        let height = image.height
        let sourceWidth = image.width
        guard height > 1, sourceWidth > 1 else { return nil }
        let width = max(8, min(sampleWidth, sourceWidth))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: ImageUtils.deviceRGB,
            bitmapInfo: ImageUtils.bitmapInfo
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = context.data else { return nil }
        let buffer = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var gray = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let offset = index * 4
            let b = Int(buffer[offset])
            let g = Int(buffer[offset + 1])
            let r = Int(buffer[offset + 2])
            gray[index] = UInt8((r * 299 + g * 587 + b * 114) / 1000)
        }
        return ImageRowSignature(width: width, height: height, gray: gray)
    }

    /// Mean absolute luminance difference between two row ranges.
    static func meanDifference(
        _ previous: ImageRowSignature,
        previousStart: Int,
        _ next: ImageRowSignature,
        nextStart: Int,
        length: Int,
        sampleRows: Int
    ) -> Double {
        guard length > 0 else { return .infinity }
        let columns = min(previous.width, next.width)
        guard columns > 0 else { return .infinity }
        let step = max(1, length / max(1, sampleRows))
        var total = 0
        var count = 0
        previous.gray.withUnsafeBufferPointer { a in
            next.gray.withUnsafeBufferPointer { b in
                var index = 0
                while index < length {
                    let rowA = previousStart + index
                    let rowB = nextStart + index
                    if rowA < 0 || rowA >= previous.height || rowB < 0 || rowB >= next.height { break }
                    let baseA = rowA * previous.width
                    let baseB = rowB * next.width
                    for column in 0..<columns {
                        total += abs(Int(a[baseA + column]) - Int(b[baseB + column]))
                    }
                    count += columns
                    index += step
                }
            }
        }
        guard count > 0 else { return .infinity }
        return Double(total) / Double(count)
    }

    static func areNearlyIdentical(_ a: ImageRowSignature, _ b: ImageRowSignature, tolerance: Double = identicalTolerance) -> Bool {
        let length = min(a.height, b.height)
        guard length > 0 else { return false }
        let diff = meanDifference(a, previousStart: a.height - length, b, nextStart: b.height - length, length: length, sampleRows: 64)
        return diff <= tolerance
    }

    /// Finds where the bottom block of the previous frame reappears inside the next frame.
    ///
    /// A fixed-height window taken from the bottom of the previous frame is slid over the next
    /// frame and the offset with the smallest mean luminance difference wins. Working with a fixed
    /// window (instead of the largest matching overlap) keeps the result stable when only a couple
    /// of rows are misaligned, and sliding the window tolerates non-scrolling chrome such as sticky
    /// headers at the top of the captured region.
    static func findMatch(
        previous: ImageRowSignature,
        next: ImageRowSignature,
        windowSize: Int? = nil,
        tolerance: Double = defaultTolerance
    ) -> StitchMatch? {
        let preferred = windowSize ?? max(32, min(96, previous.height / 3))
        let window = min(preferred, previous.height, next.height)
        guard window >= 8 else { return nil }
        let maxOffset = next.height - window
        guard maxOffset >= 0 else { return nil }
        let previousStart = previous.height - window

        func score(_ offset: Int, sampleRows: Int) -> Double {
            meanDifference(
                previous,
                previousStart: previousStart,
                next,
                nextStart: offset,
                length: window,
                sampleRows: sampleRows
            )
        }

        // Full scan with a reduced row sample (cheap), then a dense refinement around the winner.
        var bestOffset = 0
        var bestScore = Double.infinity
        for candidate in 0...maxOffset {
            let value = score(candidate, sampleRows: 16)
            if value < bestScore - 1e-9 {
                bestScore = value
                bestOffset = candidate
            }
        }

        let lower = max(0, bestOffset - 3)
        let upper = min(maxOffset, bestOffset + 3)
        if lower <= upper {
            for candidate in lower...upper {
                let value = score(candidate, sampleRows: window)
                if value < bestScore - 1e-9 {
                    bestScore = value
                    bestOffset = candidate
                }
            }
        }

        guard bestScore <= tolerance else { return nil }
        return StitchMatch(previousStart: previousStart, nextStart: bestOffset, length: window)
    }

    /// Draws the next frame underneath the accumulated image, keeping only its new rows.
    static func compose(previous: CGImage, next: CGImage, match: StitchMatch) -> CGImage? {
        let newRows = match.appendedRows(nextHeight: next.height)
        guard newRows > 0 else { return previous }
        let width = max(previous.width, next.width)
        let height = previous.height + newRows
        guard let context = ImageUtils.makeContext(width: width, height: height) else { return nil }
        context.interpolationQuality = .none
        context.draw(next, in: CGRect(x: 0, y: 0, width: CGFloat(next.width), height: CGFloat(next.height)))
        context.draw(previous, in: CGRect(x: 0, y: CGFloat(newRows), width: CGFloat(previous.width), height: CGFloat(previous.height)))
        return context.makeImage()
    }
}
