import AppKit
import CoreGraphics

/// Live preview of the stitched long image, floating beside the captured region while the user
/// scrolls (the Feishu arrangement).
///
/// The panel starts small and grows with the capture — it never shows a tall empty box — and the
/// progress text / scroll hints live in its caption. It is click-through and excluded from the
/// captures, so it never interferes with scrolling or ends up inside the stitched image.
final class ScrollingPreviewController {
    private var panel: NSPanel?
    private let previewView = ScrollPreviewView()
    private let captionLabel = NSTextField(labelWithString: "")
    private let width: CGFloat = 176
    private let captionHeight: CGFloat = 24
    private let edgeInset: CGFloat = 6
    private let minimumHeight: CGFloat = 120
    private var topEdge: CGFloat = 0
    private var visibleFrame: CGRect = .zero
    private var lastCaption: String?

    var panelWindowNumber: Int? { panel?.windowNumber }
    /// Exposed so the panel layout can be rendered in tests.
    var panelContentView: NSView? { panel?.contentView }

    func show(near region: CGRect) {
        let screen = ScreenGeometry.screen(bestMatching: region) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        visibleFrame = visible

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: width, height: minimumHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Click-through: the pointer can stay over the preview while the user keeps scrolling.
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true

        let container = NSView(frame: CGRect(x: 0, y: 0, width: width, height: minimumHeight))
        container.wantsLayer = true
        container.autoresizesSubviews = true
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        container.layer?.masksToBounds = true

        previewView.autoresizingMask = [.width, .height]
        captionLabel.font = .systemFont(ofSize: 10.5)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.alignment = .center
        captionLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(previewView)
        container.addSubview(captionLabel)
        panel.contentView = container

        var origin = CGPoint(x: region.maxX + 16, y: region.midY - minimumHeight / 2)
        if origin.x + width > visible.maxX - 12 {
            let left = region.minX - width - 16
            if left >= visible.minX + 12 {
                origin.x = left
            } else {
                origin.x = visible.maxX - width - 12
            }
        }
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - minimumHeight - 12)
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: minimumHeight)), display: false)
        topEdge = origin.y + minimumHeight

        layoutViews()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func update(
        snapshot: ScrollStitchSession.PreviewSnapshot,
        frames: Int,
        height: Int,
        status: String?
    ) {
        previewView.update(snapshot: snapshot)
        let caption = status ?? Self.progressText(frames: frames, height: height)
        if caption != lastCaption {
            lastCaption = caption
            captionLabel.stringValue = caption
            captionLabel.textColor = status == nil ? .secondaryLabelColor : .labelColor
        }
        resizePanel(for: snapshot)
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    // MARK: - Layout

    private func resizePanel(for snapshot: ScrollStitchSession.PreviewSnapshot) {
        guard let panel else { return }
        let previewWidth = width - edgeInset * 2
        let contentWidth = max(1, previewWidth - ScrollPreviewView.contentInset * 2)
        let scale = contentWidth / CGFloat(max(snapshot.frameWidth, 1))
        let documentHeight = CGFloat(max(snapshot.bottom - snapshot.top, 0)) * scale
        let desired = documentHeight + ScrollPreviewView.contentInset * 2 + captionHeight
        let maximum = max(160, visibleFrame.height * 0.62)
        let newHeight = min(max(minimumHeight, desired), maximum)
        guard abs(panel.frame.height - newHeight) > 0.5 else { return }

        // Grow downwards, keeping the top edge where it was placed next to the region.
        var originY = topEdge - newHeight
        originY = max(originY, visibleFrame.minY + 12)
        panel.setFrame(
            CGRect(x: panel.frame.minX, y: originY, width: width, height: newHeight),
            display: true
        )
        layoutViews()
    }

    private func layoutViews() {
        guard let container = panel?.contentView else { return }
        let bounds = container.bounds
        captionLabel.frame = CGRect(x: edgeInset, y: 4, width: bounds.width - edgeInset * 2, height: 16)
        previewView.frame = CGRect(
            x: edgeInset,
            y: captionHeight,
            width: bounds.width - edgeInset * 2,
            height: max(0, bounds.height - captionHeight)
        )
    }

    private static func progressText(frames: Int, height: Int) -> String {
        L10n.t(.scrollingCaptureProgress, lang: AppLanguage.current)
            .replacingOccurrences(of: "{count}", with: String(frames))
            .replacingOccurrences(of: "{height}", with: String(height))
    }
}

/// Draws the stitched document inside the preview panel: scaled to the panel width, top-anchored
/// while it is short and following the growing end once it becomes taller than the panel, so the
/// newest rows stay visible while scrolling — like the image being generated in real time.
final class ScrollPreviewView: NSView {
    static let contentInset: CGFloat = 8

    private var snapshot: ScrollStitchSession.PreviewSnapshot?

    override var isOpaque: Bool { false }

    func update(snapshot: ScrollStitchSession.PreviewSnapshot) {
        guard self.snapshot?.frames.count != snapshot.frames.count
            || self.snapshot?.top != snapshot.top
            || self.snapshot?.bottom != snapshot.bottom
            || self.snapshot?.staticCells != snapshot.staticCells
        else { return }
        self.snapshot = snapshot
        needsDisplay = true
    }

    /// Where the stitched document is painted inside the view.
    struct PreviewLayout {
        /// View points per image pixel.
        let scale: CGFloat
        /// View-space y of the document's top edge.
        let topY: CGFloat
        /// Document height in view points.
        let totalHeight: CGFloat
        /// Whether the document is growing at the bottom (scrolling down) or the top (scrolling up).
        let growsAtBottom: Bool
    }

    func layout(in bounds: CGRect) -> PreviewLayout? {
        guard let snapshot, !snapshot.frames.isEmpty,
              snapshot.frameWidth > 0, snapshot.frameHeight > 0 else { return nil }
        let contentRect = bounds.insetBy(dx: Self.contentInset, dy: Self.contentInset)
        guard contentRect.width > 8, contentRect.height > 8 else { return nil }

        let scale = contentRect.width / CGFloat(snapshot.frameWidth)
        let totalHeight = CGFloat(snapshot.bottom - snapshot.top) * scale
        // Follow the end the document is growing from: scrolling up (the default) prepends rows at
        // the top, so the newest rows sit against the top edge; scrolling down appends at the
        // bottom, so the newest rows stay against the bottom edge.
        let growsAtBottom = snapshot.lastShift > 0
        let topY: CGFloat
        if totalHeight <= contentRect.height {
            topY = contentRect.maxY
        } else if growsAtBottom {
            topY = contentRect.minY + totalHeight
        } else {
            topY = contentRect.maxY
        }
        return PreviewLayout(scale: scale, topY: topY, totalHeight: totalHeight, growsAtBottom: growsAtBottom)
    }


    /// Clip path covering only the moving cells of one frame, in view coordinates.
    private func clipPath(
        frameTop: Int,
        snapshot: ScrollStitchSession.PreviewSnapshot,
        contentRect: CGRect,
        topY: CGFloat,
        scale: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        guard snapshot.cellRows > 0, snapshot.cellColumns > 0,
              snapshot.staticCells.count == snapshot.cellRows * snapshot.cellColumns else { return path }
        let cellHeight = max(1, Int(ceil(Double(snapshot.frameHeight) / Double(snapshot.cellRows))))
        for cellRow in 0..<snapshot.cellRows {
            let rowStart = cellRow * cellHeight
            let rowEnd = min(snapshot.frameHeight, rowStart + cellHeight)
            guard rowEnd > rowStart else { continue }
            let y = topY - CGFloat(frameTop + rowEnd - snapshot.top) * scale
            let height = CGFloat(rowEnd - rowStart) * scale
            let cellBase = cellRow * snapshot.cellColumns
            var runStart: Int?
            var runEnd = 0
            for column in 0...snapshot.cellColumns {
                let moving = column < snapshot.cellColumns && !snapshot.staticCells[cellBase + column]
                if moving {
                    if runStart == nil {
                        runStart = Int(CGFloat(column) / CGFloat(snapshot.cellColumns) * contentRect.width)
                    }
                    runEnd = Int(CGFloat(column + 1) / CGFloat(snapshot.cellColumns) * contentRect.width)
                } else if let start = runStart {
                    path.addRect(CGRect(
                        x: contentRect.minX + CGFloat(start),
                        y: y,
                        width: CGFloat(runEnd - start),
                        height: height
                    ))
                    runStart = nil
                }
            }
        }
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let snapshot, let layout = layout(in: bounds),
              let context = NSGraphicsContext.current?.cgContext else { return }
        let contentRect = bounds.insetBy(dx: Self.contentInset, dy: Self.contentInset)
        let scale = layout.scale
        let topY = layout.topY
        let totalHeight = layout.totalHeight
        let growsAtBottom = layout.growsAtBottom

        context.saveGState()
        context.addPath(CGPath(roundedRect: contentRect, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.clip()
        context.interpolationQuality = .high

        guard let base = snapshot.frames.first else {
            context.restoreGState()
            return
        }

        // Areas beyond the captured screenful take the window's background colour: fixed chrome is
        // not repeated there.
        context.setFillColor(snapshot.backgroundColor)
        context.fill(contentRect)

        func viewRect(frameTop: Int) -> CGRect {
            let height = CGFloat(snapshot.frameHeight) * scale
            return CGRect(
                x: contentRect.minX,
                y: topY - CGFloat(frameTop - snapshot.top) * scale - height,
                width: contentRect.width,
                height: height
            )
        }

        context.draw(base.image, in: viewRect(frameTop: 0))

        for stored in snapshot.frames.dropFirst() {
            let cells = snapshot.staticCells
            if cells.isEmpty
                || snapshot.cellRows == 0
                || cells.count != snapshot.cellRows * snapshot.cellColumns {
                context.draw(stored.image, in: viewRect(frameTop: stored.top))
                continue
            }
            context.saveGState()
            context.addPath(clipPath(
                frameTop: stored.top,
                snapshot: snapshot,
                contentRect: contentRect,
                topY: topY,
                scale: scale
            ))
            context.clip()
            context.draw(stored.image, in: viewRect(frameTop: stored.top))
            context.restoreGState()
        }
        context.restoreGState()

        if totalHeight > contentRect.height {
            // A thin rail hints that the preview follows the newest rows.
            let track = CGRect(x: contentRect.maxX - 2, y: contentRect.minY, width: 2, height: contentRect.height)
            context.setFillColor(NSColor.white.withAlphaComponent(0.12).cgColor)
            context.fill(track)
            let thumbHeight = max(18, contentRect.height * (contentRect.height / totalHeight))
            context.setFillColor(NSColor.white.withAlphaComponent(0.55).cgColor)
            // The thumb sits at the end that is being generated.
            let thumbY = growsAtBottom ? contentRect.minY : contentRect.maxY - thumbHeight
            context.fill(CGRect(x: track.minX, y: thumbY, width: track.width, height: thumbHeight))
        }
    }
}
