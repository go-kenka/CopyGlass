import Foundation
import AppKit
import CoreGraphics
import CoreText

/// Maps image pixel space (top-left origin) into a drawing context.
struct CanvasTransform: Equatable {
    /// Image pixels to view points.
    var scale: CGFloat
    /// View-space position of the image top-left corner.
    var origin: CGPoint
    var imageSize: CGSize

    static func fitting(imageSize: CGSize, in viewSize: CGSize, padding: CGFloat = 0) -> CanvasTransform {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return CanvasTransform(scale: 1, origin: .zero, imageSize: imageSize)
        }
        let available = CGSize(
            width: max(1, viewSize.width - padding * 2),
            height: max(1, viewSize.height - padding * 2)
        )
        let raw = min(available.width / imageSize.width, available.height / imageSize.height)
        let scale = min(raw, 1.0)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (viewSize.width - drawn.width) / 2,
            y: (viewSize.height - drawn.height) / 2
        )
        return CanvasTransform(scale: scale, origin: origin, imageSize: imageSize)
    }

    func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        guard scale > 0 else { return .zero }
        return CGPoint(
            x: (viewPoint.x - origin.x) / scale,
            y: (origin.y + imageSize.height * scale - viewPoint.y) / scale
        )
    }

    func viewPoint(from imagePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x + imagePoint.x * scale,
            y: origin.y + (imageSize.height - imagePoint.y) * scale
        )
    }

    func viewRect(fromImageRect rect: CGRect) -> CGRect {
        CGRect(
            x: origin.x + rect.minX * scale,
            y: origin.y + (imageSize.height - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}

/// Draws the captured image plus its annotations using CoreGraphics. The same code path is used for
/// the on-screen canvas (live editing) and for exporting the flattened result.
enum AnnotationRenderer {
    static func render(base: CGImage, shapes: [AnnotationShape]) -> CGImage? {
        guard !shapes.isEmpty else { return base }
        guard let context = ImageUtils.makeContext(width: base.width, height: base.height) else { return nil }
        let transform = CanvasTransform(
            scale: 1,
            origin: .zero,
            imageSize: CGSize(width: base.width, height: base.height)
        )
        draw(base: base, shapes: shapes, ocrBoxes: [], in: context, transform: transform)
        return context.makeImage()
    }

    static func draw(
        base: CGImage,
        shapes: [AnnotationShape],
        ocrBoxes: [CGRect] = [],
        selection: AnnotationShape? = nil,
        hovered: AnnotationShape? = nil,
        in context: CGContext,
        transform: CanvasTransform
    ) {
        context.saveGState()
        apply(transform, to: context)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        drawUpright(base, in: CGRect(origin: .zero, size: transform.imageSize), context: context)

        for shape in shapes {
            switch shape.tool {
            case .mosaic:
                drawMosaic(shape, base: base, context: context)
            default:
                draw(shape, context: context)
            }
        }

        if selection != nil || hovered != nil {
            drawAffordances(
                selection: selection,
                hovered: hovered,
                in: context,
                scale: transform.scale
            )
        }

        if !ocrBoxes.isEmpty {
            context.saveGState()
            context.setLineWidth(max(1, 2 / max(transform.scale, 0.01)))
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.9).cgColor)
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.08).cgColor)
            for box in ocrBoxes {
                context.addRect(box)
                context.drawPath(using: .fillStroke)
            }
            context.restoreGState()
        }

        context.restoreGState()
    }

    /// Draws the select/move affordances for the editing overlay: a light outline around the shape
    /// under the pointer, and an accent outline plus handles for the selected one.
    ///
    /// Called with the annotation transform already applied, so the chrome is scaled back down by
    /// the image-to-screen scale factor to stay a constant size on screen.
    static func drawAffordances(
        selection: AnnotationShape?,
        hovered: AnnotationShape?,
        in context: CGContext,
        scale: CGFloat
    ) {
        let factor = max(scale, 0.01)
        let hairline = 1.5 / factor

        if let hovered, hovered.id != selection?.id {
            let bounds = AnnotationHitTester.displayBounds(for: hovered).insetBy(dx: -3 / factor, dy: -3 / factor)
            if bounds.width > 0, bounds.height > 0 {
                context.saveGState()
                context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.5).cgColor)
                context.setLineWidth(hairline)
                context.addPath(CGPath(roundedRect: bounds, cornerWidth: 3 / factor, cornerHeight: 3 / factor, transform: nil))
                context.strokePath()
                context.restoreGState()
            }
        }

        guard let selection else { return }
        let bounds = AnnotationHitTester.displayBounds(for: selection)
        guard bounds.width > 0, bounds.height > 0 else { return }

        context.saveGState()
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(hairline)
        context.addPath(CGPath(rect: bounds.insetBy(dx: -2 / factor, dy: -2 / factor), transform: nil))
        context.strokePath()
        context.restoreGState()

        let handles = AnnotationHitTester.handles(for: selection)
        guard !handles.isEmpty else { return }
        let size = 8 / factor
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(hairline)
        for (_, point) in handles {
            let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: size * 0.25, cornerHeight: size * 0.25, transform: nil))
            context.drawPath(using: .fillStroke)
        }
        context.restoreGState()
    }

    /// Feishu-style cursor marker: four short arms with a gap in the middle so the pixel under the
    /// cursor stays readable. Drawn in plain view coordinates, so no transform is applied.
    static func drawCursorCrosshair(
        at point: CGPoint,
        in context: CGContext,
        arm: CGFloat = 9,
        gap: CGFloat = 3,
        scale: CGFloat = 1
    ) {
        let lineWidth = max(1, 1.5 / max(scale, 0.01))
        let directions: [(CGFloat, CGFloat)] = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        context.saveGState()
        context.setLineCap(.round)
        // Dark halo first so the marker stays visible on light and dark content alike.
        let passes: [(CGFloat, NSColor)] = [
            (lineWidth * 3, NSColor.black.withAlphaComponent(0.5)),
            (lineWidth, NSColor.white)
        ]
        for (width, color) in passes {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            for (dx, dy) in directions {
                context.move(to: CGPoint(x: point.x + dx * gap, y: point.y + dy * gap))
                context.addLine(to: CGPoint(x: point.x + dx * arm, y: point.y + dy * arm))
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    static func apply(_ transform: CanvasTransform, to context: CGContext) {
        let scale = transform.scale
        context.translateBy(x: transform.origin.x, y: transform.origin.y + transform.imageSize.height * scale)
        context.scaleBy(x: scale, y: -scale)
    }

    /// Draws an image upright inside a context whose CTM already points down (top-left origin).
    static func drawUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }

    // MARK: - Shape drawing

    private static func draw(_ shape: AnnotationShape, context: CGContext) {
        switch shape.tool {
        case .rectangle:
            guard let rect = twoPointRect(shape) else { return }
            context.saveGState()
            configureStroke(shape, context: context)
            let path = CGPath(rect: rect, transform: nil)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()

        case .ellipse:
            guard let rect = twoPointRect(shape) else { return }
            context.saveGState()
            configureStroke(shape, context: context)
            context.addEllipse(in: rect)
            context.strokePath()
            context.restoreGState()

        case .arrow:
            guard shape.points.count >= 2 else { return }
            let start = shape.points[0]
            let end = shape.points[shape.points.count - 1]
            context.saveGState()
            configureStroke(shape, context: context)
            context.setLineWidth(shape.lineWidth)
            context.setStrokeColor(shape.color.cgColor)
            context.setFillColor(shape.color.cgColor)
            context.setLineCap(.round)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()

            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = max(12, shape.lineWidth * 4.5)
            let headAngle = CGFloat.pi / 7
            let point1 = CGPoint(
                x: end.x - headLength * cos(angle - headAngle),
                y: end.y - headLength * sin(angle - headAngle)
            )
            let point2 = CGPoint(
                x: end.x - headLength * cos(angle + headAngle),
                y: end.y - headLength * sin(angle + headAngle)
            )
            context.move(to: end)
            context.addLine(to: point1)
            context.addLine(to: point2)
            context.closePath()
            context.fillPath()
            context.restoreGState()

        case .pen, .highlighter:
            guard shape.points.count >= 2 else { return }
            context.saveGState()
            let isHighlighter = shape.tool == .highlighter
            let color = isHighlighter ? shape.color.withAlpha(0.35) : shape.color
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(isHighlighter ? shape.lineWidth * 3 : shape.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: shape.points[0])
            for point in shape.points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
            context.restoreGState()

        case .text:
            guard let text = shape.text, !text.isEmpty, let origin = shape.points.first else { return }
            drawText(text, at: origin, fontSize: fontSize(forLineWidth: shape.lineWidth), color: shape.color.nsColor, context: context)

        case .number:
            guard let center = shape.points.first else { return }
            let radius = max(14, shape.lineWidth * 5)
            context.saveGState()
            context.setFillColor(shape.color.cgColor)
            context.fillEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.restoreGState()
            let label = "\(shape.label ?? 1)"
            let fontSize = radius * 1.15
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let attributed = NSAttributedString(string: label, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributed)
            // The glyph is drawn with its baseline at the given point, so centring means placing
            // that baseline by the glyph's optical box rather than guessing an offset.
            let glyphBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            drawText(
                attributed,
                at: CGPoint(x: center.x - glyphBounds.midX, y: center.y + glyphBounds.midY),
                context: context
            )

        case .mosaic:
            break

        case .select:
            // The pointer tool never produces a shape.
            break
        }
    }

    private static func drawMosaic(_ shape: AnnotationShape, base: CGImage, context: CGContext) {
        guard let rect = twoPointRect(shape), rect.width >= 3, rect.height >= 3 else { return }
        let block = max(6, shape.blockSize)
        let smallWidth = max(1, Int((rect.width / block).rounded()))
        let smallHeight = max(1, Int((rect.height / block).rounded()))
        guard let cropped = ImageUtils.crop(base, topLeftRect: rect),
              let smallContext = ImageUtils.makeContext(width: smallWidth, height: smallHeight) else { return }
        smallContext.interpolationQuality = .medium
        drawUpright(cropped, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight), context: smallContext)
        guard let small = smallContext.makeImage() else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.clip(to: rect)
        drawUpright(small, in: rect, context: context)
        context.restoreGState()
    }

    /// Font size used for text annotations, shared by drawing and hit testing. The stroke picker in
    /// the toolbar doubles as the text size: 2 / 4 / 8 map to 20 / 32 / 64 image pixels.
    static func fontSize(forLineWidth lineWidth: CGFloat) -> CGFloat {
        max(20, lineWidth * 8)
    }

    // MARK: - Text metrics

    static func textAttributes(fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color
        ]
    }

    /// The area a text annotation covers, in image pixel space (top-left origin).
    static func textBounds(for shape: AnnotationShape) -> CGRect? {
        guard shape.tool == .text, let text = shape.text, !text.isEmpty, let origin = shape.points.first else {
            return nil
        }
        let attributed = NSAttributedString(
            string: text,
            attributes: textAttributes(fontSize: fontSize(forLineWidth: shape.lineWidth), color: .black)
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        guard glyphBounds.width > 0, glyphBounds.height > 0 else { return nil }
        // drawText puts the baseline at the origin point; the glyph box grows up and to the right.
        return CGRect(
            x: origin.x + glyphBounds.minX,
            y: origin.y - glyphBounds.maxY,
            width: glyphBounds.width,
            height: glyphBounds.height
        )
    }

    private static func twoPointRect(_ shape: AnnotationShape) -> CGRect? {
        guard shape.points.count >= 2 else { return nil }
        let rect = CGRect(point: shape.points[0], point: shape.points[shape.points.count - 1])
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return rect
    }

    private static func configureStroke(_ shape: AnnotationShape, context: CGContext) {
        context.setStrokeColor(shape.color.cgColor)
        context.setLineWidth(shape.lineWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)
    }

    private static func drawText(_ string: String, at point: CGPoint, fontSize: CGFloat, color: NSColor, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color
        ]
        drawText(NSAttributedString(string: string, attributes: attributes), at: point, context: context)
    }

    private static func drawText(_ attributed: NSAttributedString, at point: CGPoint, context: CGContext) {
        let line = CTLineCreateWithAttributedString(attributed)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: point.x, y: point.y)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
