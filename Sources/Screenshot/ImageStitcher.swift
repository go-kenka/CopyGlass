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

/// Signed vertical displacement between two consecutive frames of a scrolling capture.
///
/// `rows` is positive when the content moved up (the user scrolled down, new content enters from
/// the bottom) and negative when the content moved down (the user scrolled up, new content enters
/// from the top).
struct VerticalShift: Equatable {
    let rows: Int
    /// Mean absolute luminance difference of the winning overlap; lower is better.
    let score: Double
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

    /// Estimates the signed vertical displacement between two consecutive frames of a scrolling
    /// capture (see `VerticalShift`).
    ///
    /// Several fixed windows taken from the previous frame are slid over the next frame; the window
    /// with the best match wins. Anchors are kept away from the very top and bottom so sticky
    /// headers, toolbars and scrollbars — which do not move with the page — cannot dominate the
    /// score. The same routine covers both scroll directions, so no direction hint is needed.
    /// `expectedRows` is a motion prior: either the previous accepted shift (continuity) or the
    /// pixel distance predicted from the system scroll events. When `expectedTolerance` is given
    /// (event prediction) only alignments inside that window are considered, which is what keeps
    /// repetitive lists from locking onto a wrong periodic offset.
    static func estimateShift(
        previous: ImageRowSignature,
        next: ImageRowSignature,
        tolerance: Double = defaultTolerance,
        verificationTolerance: Double = 16,
        expectedRows: Int? = nil,
        expectedTolerance: Int? = nil
    ) -> VerticalShift? {
        guard previous.height == next.height, previous.height > 32, next.height > 32 else { return nil }
        let height = previous.height
        let window = max(16, min(160, height / 4))
        let maxShift = height - window
        guard maxShift > 0 else { return nil }
        let maxOffset = next.height - window
        guard maxOffset >= 0 else { return nil }

        // Anchors spread over the previous frame. A frame whose content moved by `d` rows matches
        // the anchor starting at row `a` at offset `a - d` in the next frame.
        let anchors = [maxShift, (maxShift * 2) / 3, maxShift / 3]
        var candidates: [(shift: Int, score: Double)] = []

        for anchor in anchors {
            guard isInformative(previous, start: anchor, length: window) else { continue }

            // Keep the two best, well-separated coarse offsets: a repeating layout can make the
            // true offset score only second best, and verification below knows which one is real.
            var coarse: [(offset: Int, score: Double)] = []
            for candidate in 0...maxOffset {
                let score = meanDifference(
                    previous,
                    previousStart: anchor,
                    next,
                    nextStart: candidate,
                    length: window,
                    sampleRows: 12
                )
                guard score < tolerance * 2 else { continue }
                coarse.append((candidate, score))
                if coarse.count > 24 {
                    coarse.sort { $0.score < $1.score }
                    coarse.removeLast(coarse.count - 12)
                }
            }
            coarse.sort { $0.score < $1.score }

            var refinedCount = 0
            for entry in coarse {
                guard refinedCount < 2 else { break }
                var refinedOffset = entry.offset
                var refinedScore = entry.score
                let lower = max(0, entry.offset - 3)
                let upper = min(maxOffset, entry.offset + 3)
                if lower <= upper {
                    for candidate in lower...upper {
                        let score = meanDifference(
                            previous,
                            previousStart: anchor,
                            next,
                            nextStart: candidate,
                            length: window,
                            sampleRows: window
                        )
                        if score < refinedScore {
                            refinedScore = score
                            refinedOffset = candidate
                        }
                    }
                }
                guard refinedScore <= tolerance else { continue }
                let shift = anchor - refinedOffset
                guard !candidates.contains(where: { $0.shift == shift }) else {
                    refinedCount += 1
                    continue
                }
                candidates.append((shift, refinedScore))
                refinedCount += 1
            }
        }

        // A short window can line up by coincidence (repeating rows, flat areas), so every candidate
        // is confirmed against the whole overlap. The median row difference is used so that fixed
        // chrome inside the region (sticky headers, toolbars) cannot veto a true alignment.
        var verified: [(rows: Int, score: Double)] = []
        var seenShifts = Set<Int>()
        for candidate in candidates.sorted(by: { $0.score < $1.score }) {
            guard seenShifts.insert(candidate.shift).inserted else { continue }
            let verification = medianOverlapDifference(previous, next, shift: candidate.shift)
            guard verification <= verificationTolerance else { continue }
            verified.append((candidate.shift, verification))
        }
        guard !verified.isEmpty else { return nil }

        if let expectedRows, let expectedTolerance {
            // A prediction from the real scroll events: only alignments close to it are allowed, so
            // periodic content cannot pick a different period.
            let window = max(16, expectedTolerance)
            let near = verified.filter { abs($0.rows - expectedRows) <= window }
            if let best = near.min(by: { $0.score < $1.score }) {
                return VerticalShift(rows: best.rows, score: best.score)
            }
            // Nothing close to the prediction: fall through to the plain (guarded) estimate so the
            // scroll sign can recalibrate instead of stalling the capture.
        } else if let expectedRows {
            // Continuity: the previous frame told us where the content was heading, so the closest
            // good alignment wins even when a periodic alias scores marginally better.
            func adjusted(_ entry: (rows: Int, score: Double)) -> Double {
                entry.score + Double(min(abs(entry.rows - expectedRows), 400)) * 0.01
            }
            guard let best = verified.min(by: { adjusted($0) < adjusted($1) }) else { return nil }
            return VerticalShift(rows: best.rows, score: best.score)
        }

        verified.sort { $0.score < $1.score }
        let best = verified[0]

        // Without a prior, a second clearly different alignment scoring almost as well means the
        // content repeats (uniform lists, periodic patterns): refusing the frame keeps duplicated
        // rows out of the long image and the capture retries on the next one.
        let minimumSeparation = 24
        if let runnerUp = verified.dropFirst().first(where: { abs($0.rows - best.rows) >= minimumSeparation }),
           runnerUp.score < best.score + 2 {
            return nil
        }
        return VerticalShift(rows: best.rows, score: best.score)
    }

    /// Median per-row luminance difference over the whole overlap implied by `shift`.
    private static func medianOverlapDifference(
        _ previous: ImageRowSignature,
        _ next: ImageRowSignature,
        shift: Int,
        sampleRows: Int = 48
    ) -> Double {
        let lower = max(0, shift)
        let upper = min(previous.height, previous.height + shift)
        let length = upper - lower
        guard length > 0 else { return .infinity }
        let columns = min(previous.width, next.width)
        guard columns > 0 else { return .infinity }

        let step = max(1, length / sampleRows)
        var scores: [Double] = []
        previous.gray.withUnsafeBufferPointer { a in
            next.gray.withUnsafeBufferPointer { b in
                var row = lower
                while row < upper {
                    let nextRow = row - shift
                    guard nextRow >= 0, nextRow < next.height else { break }
                    let baseA = row * previous.width
                    let baseB = nextRow * next.width
                    var total = 0
                    for column in 0..<columns {
                        total += abs(Int(a[baseA + column]) - Int(b[baseB + column]))
                    }
                    scores.append(Double(total) / Double(columns))
                    row += step
                }
            }
        }
        guard !scores.isEmpty else { return .infinity }
        scores.sort()
        return scores[scores.count / 2]
    }

    /// A match window made of a single flat colour carries no alignment information, so a low score
    /// over it must not be trusted.
    private static func isInformative(_ signature: ImageRowSignature, start: Int, length: Int) -> Bool {
        let end = min(start + length, signature.height)
        guard end > start, signature.width > 0 else { return false }
        let step = max(1, length / 16)
        var minimum = 255
        var maximum = 0
        signature.gray.withUnsafeBufferPointer { buffer in
            var row = start
            while row < end {
                let base = row * signature.width
                for column in 0..<signature.width {
                    let value = Int(buffer[base + column])
                    if value < minimum { minimum = value }
                    if value > maximum { maximum = value }
                }
                row += step
            }
        }
        return maximum - minimum >= 8
    }

    // MARK: - Motion between captured frames

    /// Motion measured between two consecutive frames of a scrolling capture.
    struct FrameMotion: Equatable {
        /// Signed vertical displacement (see `VerticalShift.rows`).
        let rows: Int
        /// Overlap score of the winning alignment.
        let score: Double
        /// Per-cell fixed mask, row-major (`cellRow * cellColumns + cellColumn`): a cell is fixed
        /// when its pixels did not move — a sidebar, a sticky header, a fixed bottom composer or a
        /// blank margin.
        let staticCells: [Bool]
        /// Number of cell rows (cell height = ceil(frameHeight / cellRows)).
        let cellRows: Int
        /// Number of cell columns (one per sampled signature column).
        let cellColumns: Int
    }

    /// Estimates the frame-to-frame motion and, at the same time, which columns are fixed.
    ///
    /// Captures of a whole window usually contain both scrolling content and fixed chrome (a
    /// sidebar, a sticky header, the window background). Matching the full width lets the fixed
    /// part dominate and produces wrong overlaps, and composing later repeats the fixed part. This
    /// routine first classifies every sampled column as static or moving by comparing it at the
    /// same screen rows, then estimates the vertical shift from the moving part only. The cell
    /// mask distinguishes fixed rows (a bottom composer, a sticky header), fixed columns (a
    /// sidebar) and fixed blocks, so composition can paint the chrome once instead of repeating it
    /// per captured screenful. A motion prior from the previous accepted frame breaks periodic
    /// ties, so repetitive lists cannot lock onto the wrong offset.
    static func estimateMotion(
        previous: ImageRowSignature,
        next: ImageRowSignature,
        bandCount: Int = 12,
        staticTolerance: Double = 2.5,
        tolerance: Double = 12,
        expectedRows: Int? = nil,
        expectedTolerance: Int? = nil
    ) -> FrameMotion? {
        guard previous.width == next.width, previous.height == next.height,
              previous.height > 32, previous.width >= 4 else { return nil }

        let width = previous.width
        let cellRows = max(8, min(40, previous.height / 48))
        let staticCells = cellStaticMask(
            previous: previous,
            next: next,
            tolerance: staticTolerance,
            cellRows: cellRows
        )
        let staticColumns = (0..<width).map { column in
            (0..<cellRows).allSatisfy { staticCells[$0 * width + column] }
        }
        let movingColumns = (0..<width).filter { !staticColumns[$0] }
        guard !movingColumns.isEmpty else {
            // Everything is fixed: the frames are identical apart from noise.
            return FrameMotion(
                rows: 0,
                score: 0,
                staticCells: staticCells,
                cellRows: cellRows,
                cellColumns: width
            )
        }

        // The combined moving part is far more discriminative than any single band, so it is the
        // primary estimate; the fixed fat tripe (sidebar, header) is excluded so it cannot drag the
        // offset. The uniqueness check inside estimateShift rejects periodic aliases.
        if let previousMoving = sliceColumns(previous, columns: movingColumns),
           let nextMoving = sliceColumns(next, columns: movingColumns) {
            if let shift = estimateShift(
                previous: previousMoving,
                next: nextMoving,
                tolerance: tolerance,
                expectedRows: expectedRows,
                expectedTolerance: expectedTolerance
            ) {
                return FrameMotion(
                    rows: shift.rows,
                    score: shift.score,
                    staticCells: staticCells,
                    cellRows: cellRows,
                    cellColumns: width
                )
            }
        }

        // Fallback: several independent horizontal bands agreeing on the same offset is a strong
        // signal when the combined signature alone was too ambiguous.
        let bandWidth = max(2, Int(ceil(Double(width) / Double(max(1, bandCount)))))
        var votes: [Int: Int] = [:]
        var scores: [Int: Double] = [:]
        var start = 0
        while start < width {
            let end = min(width, start + bandWidth)
            defer { start = end }
            let bandColumns = (start..<end).filter { !staticColumns[$0] }
            guard bandColumns.count >= 2,
                  let previousBand = sliceColumns(previous, columns: bandColumns),
                  let nextBand = sliceColumns(next, columns: bandColumns),
                  let shift = estimateShift(
                      previous: previousBand,
                      next: nextBand,
                      tolerance: tolerance,
                      expectedRows: expectedRows,
                      expectedTolerance: expectedTolerance
                  )
            else { continue }
            votes[shift.rows, default: 0] += 1
            scores[shift.rows] = min(scores[shift.rows] ?? .infinity, shift.score)
        }
        guard let winner = votes.max(by: { $0.value < $1.value }) else { return nil }
        let totalBands = votes.values.reduce(0, +)
        guard winner.value >= max(2, (totalBands + 1) / 2) else { return nil }
        return FrameMotion(
            rows: winner.key,
            score: scores[winner.key] ?? 0,
            staticCells: staticCells,
            cellRows: cellRows,
            cellColumns: width
        )
    }


    /// Cell-level fixed mask: sampled cells whose pixels are unchanged between the two frames.
    ///
    /// A cell is one sampled column wide and roughly 48 image rows tall, so fixed rows (a bottom
    /// composer, a top toolbar), fixed columns (a sidebar) and fixed blocks are all recognised.
    private static func cellStaticMask(
        previous: ImageRowSignature,
        next: ImageRowSignature,
        tolerance: Double,
        cellRows: Int
    ) -> [Bool] {
        let columns = min(previous.width, next.width)
        let height = min(previous.height, next.height)
        guard columns > 0, height > 0, cellRows > 0 else { return [] }
        let cellHeight = max(1, Int(ceil(Double(height) / Double(cellRows))))
        let threshold = Int(tolerance.rounded())
        var mask = [Bool](repeating: true, count: cellRows * columns)
        previous.gray.withUnsafeBufferPointer { a in
            next.gray.withUnsafeBufferPointer { b in
                for cellRow in 0..<cellRows {
                    let rowStart = cellRow * cellHeight
                    let rowEnd = min(height, rowStart + cellHeight)
                    guard rowEnd > rowStart else { continue }
                    let rowStep = max(1, (rowEnd - rowStart) / 3)
                    let cellBase = cellRow * columns
                    for column in 0..<columns {
                        var isStatic = true
                        var row = rowStart
                        while row < rowEnd {
                            let baseA = row * previous.width + column
                            let baseB = row * next.width + column
                            if abs(Int(a[baseA]) - Int(b[baseB])) > threshold {
                                isStatic = false
                                break
                            }
                            row += rowStep
                        }
                        mask[cellBase + column] = isStatic
                    }
                }
            }
        }
        return mask
    }

    /// Rebuilds a signature from a subset of columns.
    private static func sliceColumns(_ signature: ImageRowSignature, columns: [Int]) -> ImageRowSignature? {
        guard !columns.isEmpty else { return nil }
        let valid = columns.filter { $0 >= 0 && $0 < signature.width }
        guard !valid.isEmpty else { return nil }
        var gray = [UInt8](repeating: 0, count: valid.count * signature.height)
        signature.gray.withUnsafeBufferPointer { source in
            for row in 0..<signature.height {
                let sourceBase = row * signature.width
                let destinationBase = row * valid.count
                for (index, column) in valid.enumerated() {
                    gray[destinationBase + index] = source[sourceBase + column]
                }
            }
        }
        return ImageRowSignature(width: valid.count, height: signature.height, gray: gray)
    }
}
