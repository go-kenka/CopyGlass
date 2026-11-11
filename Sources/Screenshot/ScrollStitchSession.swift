import Foundation
import CoreGraphics

/// Incremental stitcher for the manual scrolling capture.
///
/// A captured window mixes scrolling content with fixed chrome: a sidebar, a sticky header, a
/// fixed bottom composer, the window background. Mainstream long-screenshot tools avoid repeating
/// that chrome; this session does too:
///
/// * consecutive frames are compared cell by cell (roughly 48 rows tall, one sampled column wide)
///   to tell fixed chrome from scrolling content;
/// * the shift is measured on the moving part only, with a motion-continuity prior and a
///   uniqueness check, so repetitive lists cannot lock onto a wrong periodic offset;
/// * when composing, the first frame is painted in full and every later frame only paints the
///   moving cells — fixed rows, fixed columns and fixed blocks are drawn once, and the extended
///   areas are filled with the capture's background colour.
final class ScrollStitchSession {
    enum Outcome: Equatable {
        /// The frame added rows to the document (only possible in one direction at a time).
        case extended(rows: Int)
        /// The frame did not move, or moved inside the area already captured.
        case unchanged
        /// The frame did not overlap the previous one enough to align (scrolled too fast).
        case noMatch
        /// Adding the frame would exceed `maxHeight`.
        case limitReached
        /// The frame had unexpected dimensions or could not be sampled.
        case failed
    }

    struct StoredFrame {
        let image: CGImage
        /// Row of the frame's top edge in document coordinates (top-down, may be negative).
        let top: Int
    }

    /// Number of sampled columns used for motion analysis.
    static let signatureWidth = 96

    let frameWidth: Int
    let frameHeight: Int
    let maxHeight: Int
    /// Most common colour of the captured window, used for the areas that extend beyond it.
    let backgroundColor: CGColor

    /// Immutable view of the stitched document, handed to the live preview panel on the main queue.
    struct PreviewSnapshot {
        let frames: [StoredFrame]
        let top: Int
        let bottom: Int
        let frameWidth: Int
        let frameHeight: Int
        /// Signed displacement of the last accepted frame: positive means the document grew at the
        /// bottom (scrolling down), negative means it grew at the top (scrolling up).
        let lastShift: Int
        /// Per-cell fixed mask (row-major), empty until motion has been observed.
        let staticCells: [Bool]
        let cellRows: Int
        let cellColumns: Int
        let backgroundColor: CGColor
    }

    private(set) var storedFrames: [StoredFrame] = []
    /// Top edge of the stitched document in frame-relative coordinates (0 is the first frame).
    private(set) var documentTop = 0
    /// Bottom edge (exclusive) of the stitched document.
    private(set) var documentBottom: Int
    private(set) var capturedFrames = 0
    private(set) var appendedRows = 0
    private(set) var lastShift = 0
    private(set) var reachedLimit = false

    private var lastSignature: ImageRowSignature
    private var lastTop = 0
    /// How often each cell was fixed across the observed frame pairs.
    private var staticCellVotes: [Int] = []
    private var cellObservations = 0
    private(set) var cellRows = 0
    private(set) var cellColumns = 0

    var stitchedHeight: Int { documentBottom - documentTop }

    var previewSnapshot: PreviewSnapshot {
        PreviewSnapshot(
            frames: storedFrames,
            top: documentTop,
            bottom: documentBottom,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            lastShift: lastShift,
            staticCells: resolvedStaticCells(),
            cellRows: cellRows,
            cellColumns: cellColumns,
            backgroundColor: backgroundColor
        )
    }

    var hasExtended: Bool { appendedRows > 0 }

    init?(firstFrame: CGImage, maxHeight: Int = 16_000) {
        guard firstFrame.width > 0, firstFrame.height > 1,
              let signature = ImageStitcher.signature(of: firstFrame, sampleWidth: Self.signatureWidth) else {
            return nil
        }
        self.frameWidth = firstFrame.width
        self.frameHeight = firstFrame.height
        self.maxHeight = maxHeight
        self.lastSignature = signature
        self.documentBottom = firstFrame.height
        self.capturedFrames = 1
        self.storedFrames = [StoredFrame(image: firstFrame, top: 0)]
        self.backgroundColor = ImageUtils.dominantColor(of: firstFrame)
    }

    /// Adds one captured frame to the stitched document.
    ///
    /// - Parameters:
    ///   - expectedRows: pixel shift predicted from the system scroll events since the previous
    ///     accepted frame. When present the aligner only searches around it, which stops repetitive
    ///     lists from latching onto the wrong periodic offset.
    ///   - expectedTolerance: search window around `expectedRows`, in rows.
    func ingest(
        _ frame: CGImage,
        expectedRows: Int? = nil,
        expectedTolerance: Int? = nil
    ) -> Outcome {
        capturedFrames += 1
        guard frame.width == frameWidth, frame.height == frameHeight else { return .failed }
        guard !reachedLimit else { return .limitReached }
        guard let signature = ImageStitcher.signature(of: frame, sampleWidth: Self.signatureWidth) else {
            return .failed
        }
        if ImageStitcher.areNearlyIdentical(lastSignature, signature) { return .unchanged }

        let continuityPrior = lastShift == 0 ? nil : lastShift
        guard let motion = ImageStitcher.estimateMotion(
            previous: lastSignature,
            next: signature,
            tolerance: 12,
            expectedRows: expectedRows ?? continuityPrior,
            expectedTolerance: expectedRows == nil ? nil : expectedTolerance
        ) else {
            return .noMatch
        }
        guard motion.rows != 0 else {
            // Only fixed columns or noise changed: nothing moved between the frames.
            lastSignature = signature
            return .unchanged
        }

        // The frame matched, so it becomes the reference for the next one even when it does not
        // extend the document (that is how scrolling back to the top stays aligned).
        lastSignature = signature
        lastTop += motion.rows
        lastShift = motion.rows
        recordStaticCells(motion)

        let newTop = lastTop
        let newBottom = newTop + frameHeight
        let extentTop = min(documentTop, newTop)
        let extentBottom = max(documentBottom, newBottom)
        guard extentBottom - extentTop <= maxHeight else {
            reachedLimit = true
            return .limitReached
        }

        let addedUp = max(0, documentTop - newTop)
        let addedDown = max(0, newBottom - documentBottom)
        guard addedUp > 0 || addedDown > 0 else { return .unchanged }

        storedFrames.append(StoredFrame(image: frame, top: newTop))
        documentTop = extentTop
        documentBottom = extentBottom
        appendedRows += addedUp + addedDown
        return .extended(rows: addedUp + addedDown)
    }

    private func recordStaticCells(_ motion: ImageStitcher.FrameMotion) {
        guard motion.cellRows > 0, motion.cellColumns > 0, !motion.staticCells.isEmpty else { return }
        if cellRows != motion.cellRows
            || cellColumns != motion.cellColumns
            || staticCellVotes.count != motion.staticCells.count {
            cellRows = motion.cellRows
            cellColumns = motion.cellColumns
            staticCellVotes = [Int](repeating: 0, count: motion.staticCells.count)
            cellObservations = 0
        }
        for index in staticCellVotes.indices where motion.staticCells[index] {
            staticCellVotes[index] += 1
        }
        cellObservations += 1
    }

    /// Cells that stayed fixed in most observed frame pairs. A majority vote keeps a blinking caret
    /// or a progress indicator from un-fixing the composer it sits in.
    func resolvedStaticCells() -> [Bool] {
        guard cellObservations > 0, !staticCellVotes.isEmpty else { return [] }
        let required = max(1, Int(ceil(Double(cellObservations) * 0.6)))
        return staticCellVotes.map { $0 >= required }
    }

    /// Composes the stored frames into one image.
    func finalImage() -> CGImage? {
        let height = stitchedHeight
        guard height > 0,
              let context = ImageUtils.makeContext(width: frameWidth, height: height),
              let base = storedFrames.first else { return nil }
        context.interpolationQuality = .none

        context.setFillColor(backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: frameWidth, height: height))

        let top = documentTop
        let frameHeight = self.frameHeight
        let frameWidth = self.frameWidth

        func viewRect(frameTop: Int) -> CGRect {
            CGRect(
                x: 0,
                y: CGFloat(height - (frameTop - top) - frameHeight),
                width: CGFloat(frameWidth),
                height: CGFloat(frameHeight)
            )
        }

        context.draw(base.image, in: viewRect(frameTop: 0))

        let cells = resolvedStaticCells()
        for stored in storedFrames.dropFirst() {
            if cells.count != cellRows * cellColumns || cells.isEmpty {
                context.draw(stored.image, in: viewRect(frameTop: stored.top))
                continue
            }
            context.saveGState()
            context.addPath(clipPath(frameTop: stored.top, cells: cells))
            context.clip()
            context.draw(stored.image, in: viewRect(frameTop: stored.top))
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// Clip path covering only the moving cells of one frame, in document coordinates.
    private func clipPath(frameTop: Int, cells: [Bool]) -> CGPath {
        let path = CGMutablePath()
        guard cellRows > 0, cellColumns > 0, cells.count == cellRows * cellColumns else { return path }
        let cellHeight = max(1, Int(ceil(Double(frameHeight) / Double(cellRows))))
        let height = stitchedHeight
        let top = documentTop
        let frameWidth = self.frameWidth

        for cellRow in 0..<cellRows {
            let rowStart = cellRow * cellHeight
            let rowEnd = min(frameHeight, rowStart + cellHeight)
            guard rowEnd > rowStart else { continue }
            let y = CGFloat(height - (frameTop + rowEnd - top))
            let cellBase = cellRow * cellColumns

            var runStart: Int?
            var runEnd = 0
            for column in 0...cellColumns {
                let moving = column < cellColumns && !cells[cellBase + column]
                if moving {
                    if runStart == nil { runStart = column * frameWidth / cellColumns }
                    runEnd = (column + 1) * frameWidth / cellColumns
                } else if let start = runStart {
                    path.addRect(CGRect(
                        x: CGFloat(start),
                        y: y,
                        width: CGFloat(runEnd - start),
                        height: CGFloat(rowEnd - rowStart)
                    ))
                    runStart = nil
                }
            }
        }
        return path
    }
}
