import Foundation
import AppKit
import CoreGraphics

/// Draws the frozen desktop together with the selection-phase decorations.
///
/// Kept separate from the view so the exact composition — in particular *which* region stays at
/// full brightness — can be rendered and asserted offscreen. Window-first capture relies on this:
/// the highlighted window must stay bright (like Feishu) while only the rest of the screen is dimmed.
enum SelectionPhaseRenderer {
    struct State {
        var bounds: CGRect
        var frozenImage: CGImage
        /// Region dragged out by the user, in view coordinates.
        var draggedSelection: CGRect?
        /// Window under the pointer, in view coordinates.
        var hoveredWindow: CGRect?
        var dimAlpha: CGFloat = 0.36
        var hoverBorderWidth: CGFloat = 2
    }

    static func draw(_ state: State, in context: CGContext) {
        drawFrozenImage(state, in: context)

        let selection = state.draggedSelection.flatMap { $0.width > 1 && $0.height > 1 ? $0 : nil }
        let hovered = state.hoveredWindow.flatMap { $0.width > 1 && $0.height > 1 ? $0 : nil }
        // Only the capture target stays bright: the dragged region, otherwise the hovered window.
        let brightRegion = selection ?? hovered

        let dimPath = CGMutablePath()
        dimPath.addRect(state.bounds)
        if let brightRegion {
            dimPath.addRect(brightRegion)
        }
        context.saveGState()
        context.addPath(dimPath)
        context.setFillColor(NSColor.black.withAlphaComponent(state.dimAlpha).cgColor)
        context.drawPath(using: brightRegion == nil ? .fill : .eoFill)
        context.restoreGState()

        // Hovered window: outline only, the pixels underneath stay undimmed.
        if selection == nil, let hovered {
            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(state.hoverBorderWidth)
            context.addPath(CGPath(roundedRect: hovered, cornerWidth: 4, cornerHeight: 4, transform: nil))
            context.strokePath()
            context.restoreGState()
        }

        if let selection {
            drawSelectionBorder(selection, width: state.hoverBorderWidth, in: context)
        }
    }

    static func drawFrozenImage(_ state: State, in context: CGContext) {
        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: state.bounds.height)
        context.scaleBy(x: 1, y: -1)
        AnnotationRenderer.drawUpright(
            state.frozenImage,
            in: CGRect(origin: .zero, size: state.bounds.size),
            context: context
        )
        context.restoreGState()
    }

    private static func drawSelectionBorder(_ selection: CGRect, width: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(rect: selection, transform: nil))
        context.strokePath()

        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(rect: selection.insetBy(dx: 1, dy: 1), transform: nil))
        context.strokePath()

        let handleSize: CGFloat = 6
        context.setFillColor(NSColor.white.cgColor)
        for point in [
            CGPoint(x: selection.minX, y: selection.minY),
            CGPoint(x: selection.maxX, y: selection.minY),
            CGPoint(x: selection.minX, y: selection.maxY),
            CGPoint(x: selection.maxX, y: selection.maxY),
            CGPoint(x: selection.midX, y: selection.minY),
            CGPoint(x: selection.midX, y: selection.maxY),
            CGPoint(x: selection.minX, y: selection.midY),
            CGPoint(x: selection.maxX, y: selection.midY)
        ] {
            context.fillEllipse(in: CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            ))
        }
        context.restoreGState()
    }
}
