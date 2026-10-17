import SwiftUI
import AppKit
import CoreGraphics
import Carbon

/// SwiftUI bridge for the AppKit annotation canvas.
struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var model: ScreenshotEditorModel

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        let view = AnnotationCanvasNSView(image: model.originalImage)
        view.onCommit = { shape in
            model.commit(shape)
        }
        view.nextLabel = { model.nextNumberLabel() }
        return view
    }

    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        nsView.shapes = model.shapes
        nsView.tool = model.tool
        nsView.color = model.color
        nsView.lineWidth = model.lineWidth
        nsView.ocrBoxes = model.showOCRBoxes ? (model.ocrResult?.blocks.map { $0.pixelBox } ?? []) : []
        nsView.needsDisplay = true
    }
}

/// Draws the capture, the committed annotations and the in-progress draft, and turns mouse input
/// into annotation shapes. All geometry is stored in image pixel space.
final class AnnotationCanvasNSView: NSView, NSTextFieldDelegate {
    let image: CGImage
    var shapes: [AnnotationShape] = []
    var tool: AnnotationTool = .rectangle
    var color: AnnotationColor = AnnotationColor.palette[0]
    var lineWidth: CGFloat = 4
    var ocrBoxes: [CGRect] = []
    var onCommit: ((AnnotationShape) -> Void)?
    var nextLabel: (() -> Int)?

    private var draft: AnnotationShape?
    private var textEditor: NSTextField?
    private var textOriginImage: CGPoint = .zero
    private var lastDragImagePoint: CGPoint = .zero

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    private var canvasTransform: CanvasTransform {
        CanvasTransform.fitting(
            imageSize: CGSize(width: image.width, height: image.height),
            in: bounds.size,
            padding: 10
        )
    }

    private func clampedImagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), CGFloat(image.width)),
            y: min(max(point.y, 0), CGFloat(image.height))
        )
    }

    private func imagePoint(from event: NSEvent) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return clampedImagePoint(canvasTransform.imagePoint(from: viewPoint))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0.13, alpha: 1).cgColor)
        context.fill(bounds)
        context.restoreGState()

        let transform = canvasTransform
        // Drop shadow around the sheet.
        context.saveGState()
        let sheet = transform.viewRect(fromImageRect: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setFillColor(NSColor(calibratedWhite: 0.05, alpha: 1).cgColor)
        context.fill(sheet.insetBy(dx: -4, dy: -4))
        context.restoreGState()

        var allShapes = shapes
        if let draft { allShapes.append(draft) }
        AnnotationRenderer.draw(base: image, shapes: allShapes, ocrBoxes: ocrBoxes, in: context, transform: transform)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitTextEditorIfNeeded()
        let imagePoint = imagePoint(from: event)
        lastDragImagePoint = imagePoint

        switch tool {
        case .text:
            beginTextEntry(at: imagePoint, viewPoint: convert(event.locationInWindow, from: nil))
        case .number:
            let shape = AnnotationShape(
                tool: .number,
                points: [imagePoint],
                color: color,
                lineWidth: lineWidth,
                label: nextLabel?() ?? 1
            )
            onCommit?(shape)
        case .pen, .highlighter:
            draft = AnnotationShape(tool: tool, points: [imagePoint], color: color, lineWidth: lineWidth)
            needsDisplay = true
        default:
            draft = AnnotationShape(tool: tool, points: [imagePoint, imagePoint], color: color, lineWidth: lineWidth)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = draft else { return }
        let imagePoint = imagePoint(from: event)
        switch tool {
        case .pen, .highlighter:
            let threshold = 1.5 / max(canvasTransform.scale, 0.01)
            if hypot(imagePoint.x - lastDragImagePoint.x, imagePoint.y - lastDragImagePoint.y) >= threshold {
                current.points.append(imagePoint)
                lastDragImagePoint = imagePoint
            }
        default:
            if current.points.count == 2 {
                current.points[1] = imagePoint
            } else {
                current.points = [current.points.first ?? imagePoint, imagePoint]
            }
        }
        draft = current
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let shape = draft else { return }
        draft = nil
        needsDisplay = true
        switch shape.tool {
        case .pen, .highlighter:
            guard shape.points.count >= 2 else { return }
        case .rectangle, .ellipse, .arrow, .mosaic:
            guard shape.points.count >= 2 else { return }
            let rect = CGRect(point: shape.points[0], point: shape.points[1])
            guard rect.width >= 2, rect.height >= 2 else { return }
        default:
            break
        }
        onCommit?(shape)
    }

    // MARK: - Text entry

    private func beginTextEntry(at imagePoint: CGPoint, viewPoint: CGPoint) {
        textOriginImage = imagePoint
        let field = NSTextField(frame: CGRect(x: viewPoint.x, y: viewPoint.y - 12, width: 180, height: 26))
        field.font = .systemFont(ofSize: max(11, lineWidth * 6 * canvasTransform.scale))
        field.textColor = color.nsColor
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.isBezeled = false
        field.drawsBackground = true
        field.focusRingType = .none
        field.placeholderString = L10n.t(.annotationTextPlaceholder, lang: AppLanguage.current)
        field.delegate = self
        addSubview(field)
        textEditor = field
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditorIfNeeded()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textEditor?.removeFromSuperview()
            textEditor = nil
            needsDisplay = true
            return true
        }
        return false
    }

    private func commitTextEditorIfNeeded() {
        guard let field = textEditor else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        textEditor = nil
        needsDisplay = true
        guard !value.isEmpty else { return }
        let shape = AnnotationShape(
            tool: .text,
            points: [textOriginImage],
            color: color,
            lineWidth: lineWidth,
            text: value
        )
        onCommit?(shape)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if textEditor != nil {
            super.keyDown(with: event)
            return
        }
        if Int(event.keyCode) == kVK_Escape {
            draft = nil
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }
}
