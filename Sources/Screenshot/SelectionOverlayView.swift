import Foundation
import AppKit
import CoreGraphics
import Carbon

/// Full-screen frozen overlay content. It renders one captured display and drives both phases of a
/// capture: the selection phase (crosshair, window highlight, magnifier) and the editing phase
/// (Feishu-style annotations drawn directly over the frozen pixels).
final class SelectionOverlayView: NSView {
    weak var controller: RegionSelectionController?
    let screen: NSScreen
    /// The frozen display content. Kept optional because the overlay window is pre-warmed (and
    /// mapped) before the capture lands; the frame is filled in by `update(image:)`.
    private(set) var image: CGImage?

    private var trackingArea: NSTrackingArea?
    private var draft: AnnotationShape?
    private var textEditor: InlineTextEditor?
    private var editingShapeID: UUID?
    private var textOriginImage: CGPoint = .zero
    private var lastDragImagePoint: CGPoint = .zero

    init(frame: NSRect, controller: RegionSelectionController, screen: NSScreen, image: CGImage?) {
        self.controller = controller
        self.screen = screen
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    /// Installs the frozen frame once the capture finished. The window is still transparent at this
    /// point, so the new content reaches the screen together with the reveal.
    func update(image: CGImage) {
        self.image = image
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    // MARK: - Geometry

    /// Selection in this view's (bottom-left origin) coordinates, clamped to the view.
    var selectionInView: CGRect {
        unclampedSelectionInView.intersection(bounds)
    }

    /// Selection in this view's coordinates without clamping (a selection may span displays).
    var unclampedSelectionInView: CGRect {
        guard let controller else { return .zero }
        return controller.selection.standardized
            .offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    /// Maps the cropped capture's pixel space onto the selection area of this view.
    var annotationTransform: CanvasTransform? {
        guard let session = controller?.session else { return nil }
        let rect = unclampedSelectionInView
        let size = session.imagePixelSize
        guard rect.width > 1, rect.height > 1, size.width > 0, size.height > 0 else { return nil }
        let scale = rect.width / size.width
        return CanvasTransform(
            scale: scale,
            origin: CGPoint(x: rect.minX, y: rect.minY),
            imageSize: size
        )
    }

    private var isEditing: Bool { controller?.phase == .editing }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        guard !isEditing else { return }
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if isEditing {
            beginEditingInteraction(at: point, in: event)
        } else {
            controller?.handleMouseDown(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if isEditing {
            updateAnnotation(at: point)
        } else {
            controller?.handleMouseDragged(to: point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if isEditing {
            commitAnnotation()
        } else {
            controller?.handleMouseUp(at: point)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if isEditing {
            controller?.updateCursor(point)
            updateHover(at: point)
        } else {
            controller?.handleMouseMoved(to: point)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if isEditing {
            controller?.cancelEditing()
        } else {
            controller?.cancel()
        }
    }

    /// Region selection owns the keyboard while it is up; unhandled keys must not beep.
    override func keyDown(with event: NSEvent) {}

    // MARK: - Annotation editing

    private func clampedImagePoint(_ point: CGPoint, transform: CanvasTransform) -> CGPoint {
        let imagePoint = transform.imagePoint(from: point)
        return CGPoint(
            x: min(max(imagePoint.x, 0), transform.imageSize.width),
            y: min(max(imagePoint.y, 0), transform.imageSize.height)
        )
    }

    /// What the current mouse gesture is doing in the editing phase.
    private enum EditGesture: Equatable {
        case none
        case drawing
        /// Clicked a text annotation: opens for typing unless the pointer travels (then it moves).
        case pendingTextEdit(id: UUID, startImagePoint: CGPoint)
        case moving(id: UUID, lastImagePoint: CGPoint)
        case resizing(id: UUID, handle: AnnotationHandle)
        /// Dragging one of the capture-frame handles, or moving the frame itself.
        case selectionResize(handle: SelectionHandle)
        case selectionMove
    }

    private var gesture: EditGesture = .none

    /// In the editing phase the capture frame stays adjustable: the border handles resize it, and a
    /// drag inside it with the pointer tool (not on an annotation) moves it. Frame handles win over
    /// annotations because they sit on the border.
    private func beginEditingInteraction(at globalPoint: CGPoint, in event: NSEvent) {
        let viewPoint = convert(globalPoint)
        if let handle = SelectionAdjustment.handle(at: viewPoint, in: unclampedSelectionInView) {
            commitTextEditorIfNeeded()
            controller?.beginSelectionAdjustment(handle: handle, at: globalPoint)
            gesture = .selectionResize(handle: handle)
            return
        }
        beginAnnotation(at: globalPoint, in: event)
    }

    private func beginAnnotation(at globalPoint: CGPoint, in event: NSEvent) {
        guard let session = controller?.session, let transform = annotationTransform else { return }
        commitTextEditorIfNeeded()
        let viewPoint = convert(globalPoint)
        guard selectionInView.insetBy(dx: -2, dy: -2).contains(viewPoint) else { return }
        let imagePoint = clampedImagePoint(viewPoint, transform: transform)
        lastDragImagePoint = imagePoint

        let intent = AnnotationHitTester.pressIntent(
            at: imagePoint,
            shapes: session.shapes,
            selected: session.selectedShape,
            tool: session.tool,
            optionHeld: event.modifierFlags.contains(.option),
            screenScale: transform.scale
        )

        switch intent {
        case .resize(let id, let handle):
            session.beginInteractiveEdit()
            gesture = .resizing(id: id, handle: handle)
            return

        case .editText(let id):
            session.select(id)
            gesture = .pendingTextEdit(id: id, startImagePoint: imagePoint)
            return

        case .move(let id):
            session.select(id)
            session.beginInteractiveEdit()
            gesture = .moving(id: id, lastImagePoint: imagePoint)
            NSCursor.closedHand.set()
            return

        case .none:
            session.select(nil)
            // Dragging the bare capture with the pointer tool moves the whole frame.
            if session.tool == .select, selectionInView.contains(viewPoint) {
                controller?.beginSelectionAdjustment(handle: nil, at: globalPoint)
                gesture = .selectionMove
            } else {
                gesture = .none
            }
            return

        case .draw:
            session.select(nil)
            gesture = .drawing
        }
        switch session.tool {
        case .text:
            beginTextEntry(at: imagePoint, session: session, transform: transform, editing: nil)
        case .number:
            gesture = .none
            session.commit(AnnotationShape(
                tool: .number,
                points: [imagePoint],
                color: session.color,
                lineWidth: session.lineWidth,
                label: session.nextBadge
            ))
        case .pen, .highlighter:
            draft = AnnotationShape(tool: session.tool, points: [imagePoint], color: session.color, lineWidth: session.lineWidth)
            needsDisplay = true
        default:
            draft = AnnotationShape(tool: session.tool, points: [imagePoint, imagePoint], color: session.color, lineWidth: session.lineWidth)
            needsDisplay = true
        }
    }

    private func updateAnnotation(at globalPoint: CGPoint) {
        guard let session = controller?.session, let transform = annotationTransform else { return }
        let imagePoint = clampedImagePoint(convert(globalPoint), transform: transform)

        switch gesture {
        case .pendingTextEdit(let id, let start):
            let travelled = hypot(imagePoint.x - start.x, imagePoint.y - start.y)
            if travelled > 4 / max(transform.scale, 0.01) {
                session.beginInteractiveEdit()
                gesture = .moving(id: id, lastImagePoint: imagePoint)
                NSCursor.closedHand.set()
            }

        case .moving(let id, let last):
            guard let shape = session.shape(with: id) else { return }
            let delta = CGSize(width: imagePoint.x - last.x, height: imagePoint.y - last.y)
            session.applyInteractiveChange(AnnotationHitTester.translate(shape, by: delta))
            gesture = .moving(id: id, lastImagePoint: imagePoint)

        case .resizing(let id, let handle):
            guard let shape = session.shape(with: id) else { return }
            session.applyInteractiveChange(AnnotationHitTester.resize(shape, handle: handle, to: imagePoint))

        case .drawing:
            guard var current = draft else { return }
            switch current.tool {
            case .pen, .highlighter:
                let threshold = 1.5 / max(transform.scale, 0.01)
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
            current.color = session.color
            current.lineWidth = session.lineWidth
            draft = current
            needsDisplay = true

        case .selectionResize, .selectionMove:
            controller?.updateSelectionAdjustment(to: globalPoint)

        case .none:
            break
        }
    }

    private func commitAnnotation() {
        guard let session = controller?.session else { return }
        switch gesture {
        case .pendingTextEdit(let id, _):
            // A plain click on a text annotation starts editing it right away.
            gesture = .none
            guard let shape = session.shape(with: id), shape.tool == .text,
                  let transform = annotationTransform else { return }
            beginTextEntry(
                at: shape.points.first ?? .zero,
                session: session,
                transform: transform,
                editing: shape
            )

        case .moving, .resizing:
            session.endInteractiveEdit()
            gesture = .none
            NSCursor.openHand.set()

        case .selectionResize, .selectionMove:
            controller?.endSelectionAdjustment()
            gesture = .none

        case .drawing:
            gesture = .none
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
            session.commit(shape)

        case .none:
            draft = nil
            needsDisplay = true
        }
    }

    /// Highlights the annotation under the pointer so it is obvious that it can be edited.
    private func updateHover(at globalPoint: CGPoint) {
        guard let session = controller?.session, let transform = annotationTransform else { return }
        guard gesture == .none, session.textEditingShapeID == nil else { return }
        let viewPoint = convert(globalPoint)
        // The capture frame handles sit on the border, above the annotations.
        if let handle = SelectionAdjustment.handle(at: viewPoint, in: unclampedSelectionInView) {
            session.setHoveredShape(nil)
            handle.cursor.set()
            return
        }
        let imagePoint = clampedImagePoint(viewPoint, transform: transform)
        let hit = AnnotationHitTester.hitTest(session.shapes, imagePoint: imagePoint)
        session.setHoveredShape(hit?.id)
        if let hit, let handle = AnnotationHitTester.handle(
            at: imagePoint,
            for: hit,
            tolerance: 9 / max(transform.scale, 0.01)
        ) {
            _ = handle
            NSCursor.crosshair.set()
        } else if hit != nil {
            NSCursor.openHand.set()
        } else if session.tool == .select, selectionInView.contains(viewPoint) {
            // Hints that the frame itself can be dragged with the pointer tool.
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func convert(_ globalPoint: CGPoint) -> CGPoint {
        CGPoint(x: globalPoint.x - screen.frame.minX, y: globalPoint.y - screen.frame.minY)
    }

    // MARK: - Text annotations

    private func beginTextEntry(
        at imagePoint: CGPoint,
        session: CaptureSession,
        transform: CanvasTransform,
        editing existing: AnnotationShape?
    ) {
        textOriginImage = imagePoint
        editingShapeID = existing?.id
        let lineWidth = existing?.lineWidth ?? session.lineWidth
        let color = existing?.color ?? session.color
        let editor = InlineTextEditor(
            text: existing?.text ?? "",
            fontSize: AnnotationRenderer.fontSize(forLineWidth: lineWidth) * transform.scale,
            textColor: color.nsColor
        )
        editor.onCommit = { [weak self] value in
            self?.finishTextEntry(with: value)
        }
        editor.onCancel = { [weak self] in
            self?.cancelTextEntry()
        }
        session.setTextEditingShape(existing?.id)
        addSubview(editor)
        let anchor = transform.viewPoint(from: imagePoint)
        editor.place(baseline: anchor.y, x: anchor.x)
        textEditor = editor
        editor.focus()
    }

    var isEditingText: Bool { textEditor != nil }

    /// Commits the inline editor if one is open (also used when the capture finishes).
    func commitTextEditorIfNeeded() {
        guard let editor = textEditor else { return }
        finishTextEntry(with: editor.stringValue)
    }

    private func finishTextEntry(with rawValue: String) {
        guard let editor = textEditor, let session = controller?.session else { return }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.removeFromSuperview()
        textEditor = nil
        session.setTextEditingShape(nil)
        needsDisplay = true

        // Re-editing an existing text annotation: replace it, or drop it when emptied.
        if let id = editingShapeID {
            editingShapeID = nil
            guard let existing = session.shape(with: id) else { return }
            if value.isEmpty {
                session.select(id)
                session.removeSelectedShape()
            } else {
                var updated = existing
                updated.text = value
                session.replace(updated)
            }
            return
        }

        guard !value.isEmpty else { return }
        session.commit(AnnotationShape(
            tool: .text,
            points: [textOriginImage],
            color: session.color,
            lineWidth: session.lineWidth,
            text: value
        ))
    }

    private func cancelTextEntry() {
        textEditor?.removeFromSuperview()
        textEditor = nil
        editingShapeID = nil
        controller?.session?.setTextEditingShape(nil)
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let controller,
              let frozenImage = image else { return }
        if controller.phase == .editing {
            drawEditingPhase(context: context, controller: controller, frozenImage: frozenImage)
        } else {
            drawSelectionPhase(context: context, controller: controller, frozenImage: frozenImage)
        }
    }

    /// Window-first selection: the hovered window (or the region being dragged) stays at full
    /// brightness while the rest of the screen is dimmed, matching the Feishu look.
    private func drawSelectionPhase(context: CGContext, controller: RegionSelectionController, frozenImage: CGImage) {
        let origin = screen.frame.origin
        let dragged = controller.selection.standardized
            .offsetBy(dx: -origin.x, dy: -origin.y)
            .intersection(bounds)
        let hovered = controller.hoveredRectLocal(to: screen)?.intersection(bounds)
        let hasSelection = dragged.width > 1 && dragged.height > 1

        SelectionPhaseRenderer.draw(
            SelectionPhaseRenderer.State(
                bounds: bounds,
                frozenImage: frozenImage,
                draggedSelection: dragged,
                hoveredWindow: hovered
            ),
            in: context
        )

        if hasSelection {
            let scale = screen.backingScaleFactor
            let label = "\(Int((dragged.width * scale).rounded())) x \(Int((dragged.height * scale).rounded()))"
            drawLabel(label, at: CGPoint(x: dragged.minX, y: dragged.maxY + 6), context: context)
        } else if let hovered, hovered.width > 1 {
            drawLabel(controller.hoveredWindowLabel, at: CGPoint(x: hovered.minX, y: hovered.maxY + 6), context: context)
        }

        drawCrosshair(cursor: controller.cursorPoint, origin: origin, context: context)
        drawHint(context: context)
        drawMagnifier(cursor: controller.cursorPoint, origin: origin, context: context, frozenImage: frozenImage)
    }

    private func drawEditingPhase(context: CGContext, controller: RegionSelectionController, frozenImage: CGImage) {
        guard let session = controller.session else { return }
        let localSelection = selectionInView
        // The frame may run past this screen (a selection spanning displays); the border and its
        // handles are drawn from the true frame and clipped to this view.
        let frameInView = unclampedSelectionInView

        SelectionPhaseRenderer.drawFrozenImage(
            SelectionPhaseRenderer.State(bounds: bounds, frozenImage: frozenImage),
            in: context
        )

        // Dim everything outside the selection.
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        dimPath.addRect(localSelection)
        context.saveGState()
        context.addPath(dimPath)
        context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.drawPath(using: .eoFill)
        context.restoreGState()

        // Captured pixels + annotations, mapped onto the selection.
        if let transform = annotationTransform {
            var shapes = session.renderableShapes
            if let draft { shapes.append(draft) }
            // The shape being typed into is drawn by the text field itself, so its outline and hover
            // highlight are suppressed as well.
            let editingID = session.textEditingShapeID
            let selection = session.selectedShape.flatMap { $0.id == editingID ? nil : $0 }
            let hovered = session.hoveredShape.flatMap { $0.id == editingID ? nil : $0 }
            context.saveGState()
            context.clip(to: localSelection)
            AnnotationRenderer.draw(
                base: session.image,
                shapes: shapes,
                ocrBoxes: session.ocrBoxes,
                selection: selection,
                hovered: hovered,
                in: context,
                transform: transform
            )
            context.restoreGState()
        }

        // Border, so the capture area stays visible against busy content.
        context.saveGState()
        context.clip(to: bounds)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(rect: frameInView.insetBy(dx: 0.5, dy: 0.5), transform: nil))
        context.strokePath()
        context.restoreGState()

        // Frame handles: the capture area can still be resized while the annotations are edited.
        drawFrameHandles(in: frameInView, context: context)
    }

    private func drawFrameHandles(in rect: CGRect, context: CGContext) {
        let side: CGFloat = 7
        let visible = bounds.insetBy(dx: -side, dy: -side)
        context.saveGState()
        for (_, point) in SelectionAdjustment.handles(for: rect) {
            guard visible.contains(point) else { continue }
            let handle = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
            let path = CGPath(roundedRect: handle, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            context.addPath(path)
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// A small crosshair follows the pointer; the screen is not covered with guide lines.
    private func drawCrosshair(cursor: CGPoint, origin: CGPoint, context: CGContext) {
        let local = CGPoint(x: cursor.x - origin.x, y: cursor.y - origin.y)
        guard bounds.contains(local) else { return }
        AnnotationRenderer.drawCursorCrosshair(
            at: local,
            in: context,
            arm: 9,
            gap: 3,
            scale: screen.backingScaleFactor
        )
    }

    private func drawHint(context: CGContext) {
        guard let controller else { return }
        let text = controller.hintText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let padding: CGFloat = 12
        let rect = CGRect(
            x: bounds.midX - (size.width + padding * 2) / 2,
            y: 48,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.setFillColor(NSColor.black.withAlphaComponent(0.66).cgColor)
        context.fillPath()
        context.restoreGState()
        attributed.draw(at: CGPoint(x: rect.minX + padding, y: rect.minY + padding / 2))
    }

    private func drawLabel(_ text: String, at point: CGPoint, context: CGContext) {
        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let padding: CGFloat = 6
        var rect = CGRect(x: point.x, y: point.y, width: size.width + padding * 2, height: size.height + 6)
        if rect.maxX > bounds.maxX - 4 {
            rect.origin.x = bounds.maxX - rect.width - 4
        }
        if rect.maxY > bounds.maxY - 4 {
            rect.origin.y = point.y - rect.height - 6
        }
        if rect.minX < bounds.minX + 4 {
            rect.origin.x = bounds.minX + 4
        }
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        context.fillPath()
        context.restoreGState()
        attributed.draw(at: CGPoint(x: rect.minX + padding, y: rect.minY + 3))
    }

    /// Small loupe showing the pixels under the cursor plus their hex color.
    private func drawMagnifier(cursor: CGPoint, origin: CGPoint, context: CGContext, frozenImage: CGImage) {
        let local = CGPoint(x: cursor.x - origin.x, y: cursor.y - origin.y)
        guard bounds.contains(local) else { return }
        let side: CGFloat = 116
        var center = CGPoint(x: local.x + 76, y: local.y - 76)
        if center.x + side / 2 > bounds.maxX - 8 { center.x = local.x - 76 }
        if center.y - side / 2 < bounds.minY + 8 { center.y = local.y + 76 }
        let radius = side / 2
        let zoom: CGFloat = 6
        let scale = screen.backingScaleFactor

        context.saveGState()
        let circle = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: side, height: side), transform: nil)
        context.addPath(circle)
        context.clip()
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: center.x - radius, y: center.y - radius, width: side, height: side))
        context.interpolationQuality = .none
        let pixelPoint = CGPoint(x: local.x * scale, y: (bounds.height - local.y) * scale)
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: zoom, y: -zoom)
        context.translateBy(x: -pixelPoint.x, y: -pixelPoint.y)
        AnnotationRenderer.drawUpright(
            frozenImage,
            in: CGRect(x: 0, y: 0, width: CGFloat(frozenImage.width), height: CGFloat(frozenImage.height)),
            context: context
        )
        context.restoreGState()

        context.saveGState()
        context.addPath(circle)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2)
        context.strokePath()
        context.restoreGState()

        let pixelX = Int(pixelPointX(cursor: cursor, origin: origin, scale: scale).rounded())
        let pixelY = Int(pixelPointY(cursor: cursor, origin: origin, scale: scale).rounded())
        var text = "\(pixelX), \(pixelY)"
        if let hex = colorHex(at: CGPoint(x: pixelX, y: pixelY), in: frozenImage) {
            text += "  \(hex)"
        }
        drawLabel(text, at: CGPoint(x: center.x - radius, y: center.y - radius - 22), context: context)
    }

    private func pixelPointX(cursor: CGPoint, origin: CGPoint, scale: CGFloat) -> CGFloat {
        (cursor.x - origin.x) * scale
    }

    private func pixelPointY(cursor: CGPoint, origin: CGPoint, scale: CGFloat) -> CGFloat {
        (screen.frame.height - (cursor.y - origin.y)) * scale
    }

    private func colorHex(at point: CGPoint, in frozenImage: CGImage) -> String? {
        let rect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        guard let pixel = ImageUtils.crop(frozenImage, topLeftRect: rect),
              let context = ImageUtils.makeContext(width: 1, height: 1) else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let raw = context.data else { return nil }
        let buffer = raw.bindMemory(to: UInt8.self, capacity: 4)
        return String(format: "#%02X%02X%02X", buffer[2], buffer[1], buffer[0])
    }
}
