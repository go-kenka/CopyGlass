import Foundation
import AppKit
import CoreGraphics

/// A grab point on the capture frame while it is being adjusted in place (after the first drag).
enum SelectionHandle: CaseIterable, Equatable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// The resize cursor shown when the handle is under the pointer. macOS 15 has proper frame
    /// resize cursors; older systems only provide straight edge cursors, so corners fall back.
    var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: frameResizePosition, directions: .all)
        }
        switch self {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return .crosshair
        }
    }

    @available(macOS 15.0, *)
    private var frameResizePosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: return .topLeft
        case .top: return .top
        case .topRight: return .topRight
        case .right: return .right
        case .bottomRight: return .bottomRight
        case .bottom: return .bottom
        case .bottomLeft: return .bottomLeft
        case .left: return .left
        }
    }
}

/// Geometry for moving/resizing the capture frame after the initial selection was drawn.
///
/// Everything works in Cocoa global coordinates (bottom-left origin), the same space the selection
/// is stored in. The helpers are pure so the interaction can be unit tested without a display.
enum SelectionAdjustment {
    /// Smallest capture frame the user can drag the handles to, in points.
    static let minimumSize: CGFloat = 16
    /// How close the pointer has to be to a handle to grab it, in points.
    static let handleTolerance: CGFloat = 10

    /// Grab tolerance for a specific frame. Small frames shrink it so their interior (moving the
    /// frame, drawing an annotation) stays reachable instead of every point being a handle.
    static func handleTolerance(for rect: CGRect) -> CGFloat {
        let rect = rect.standardized
        return min(handleTolerance, max(3, min(rect.width, rect.height) / 3))
    }

    static func handles(for rect: CGRect) -> [(handle: SelectionHandle, point: CGPoint)] {
        let rect = rect.standardized
        return [
            (.topLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.top, CGPoint(x: rect.midX, y: rect.maxY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY))
        ]
    }

    static func handle(
        at point: CGPoint,
        in rect: CGRect,
        tolerance: CGFloat? = nil
    ) -> SelectionHandle? {
        let tolerance = tolerance ?? handleTolerance(for: rect)
        var best: (handle: SelectionHandle, distance: CGFloat)?
        for (handle, handlePoint) in handles(for: rect) {
            let distance = hypot(handlePoint.x - point.x, handlePoint.y - point.y)
            guard distance <= tolerance else { continue }
            if best == nil || distance < best!.distance {
                best = (handle, distance)
            }
        }
        return best?.handle
    }

    /// Drags the given edge/corner to `point`, keeping the opposite edges fixed.
    static func resized(
        _ rect: CGRect,
        handle: SelectionHandle,
        to point: CGPoint,
        minimum: CGFloat = minimumSize
    ) -> CGRect {
        let rect = rect.standardized
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY
        switch handle {
        case .topLeft:
            minX = min(point.x, maxX - minimum)
            maxY = max(point.y, minY + minimum)
        case .top:
            maxY = max(point.y, minY + minimum)
        case .topRight:
            maxX = max(point.x, minX + minimum)
            maxY = max(point.y, minY + minimum)
        case .right:
            maxX = max(point.x, minX + minimum)
        case .bottomRight:
            maxX = max(point.x, minX + minimum)
            minY = min(point.y, maxY - minimum)
        case .bottom:
            minY = min(point.y, maxY - minimum)
        case .bottomLeft:
            minX = min(point.x, maxX - minimum)
            minY = min(point.y, maxY - minimum)
        case .left:
            minX = min(point.x, maxX - minimum)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func moved(_ rect: CGRect, by delta: CGSize) -> CGRect {
        rect.standardized.offsetBy(dx: delta.width, dy: delta.height)
    }

    /// Keeps the frame inside the given area (the union of the attached displays) and above the
    /// minimum size, so a crop can always be produced from the frozen displays.
    static func clamped(_ rect: CGRect, to bounds: CGRect, minimum: CGFloat = minimumSize) -> CGRect {
        let bounds = bounds.standardized
        guard bounds.width > 0, bounds.height > 0 else { return rect.standardized }
        var result = rect.standardized
        result.size.width = min(max(result.width, minimum), bounds.width)
        result.size.height = min(max(result.height, minimum), bounds.height)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }

    /// Maps a point from the old crop's pixel space to the new crop's pixel space. Annotations are
    /// stored in image pixels, so this keeps them on the same spot of the frozen screen while the
    /// capture frame is moved or resized.
    static func imagePointTransform(
        from oldSelection: CGRect,
        oldImageSize: CGSize,
        to newSelection: CGRect,
        newImageSize: CGSize
    ) -> (CGPoint) -> CGPoint {
        guard oldSelection.width > 0, oldSelection.height > 0,
              newSelection.width > 0, newSelection.height > 0,
              oldImageSize.width > 0, oldImageSize.height > 0,
              newImageSize.width > 0, newImageSize.height > 0 else { return { $0 } }
        let old = CanvasTransform(
            scale: oldSelection.width / oldImageSize.width,
            origin: oldSelection.origin,
            imageSize: oldImageSize
        )
        let new = CanvasTransform(
            scale: newSelection.width / newImageSize.width,
            origin: newSelection.origin,
            imageSize: newImageSize
        )
        return { imagePoint in
            new.imagePoint(from: old.viewPoint(from: imagePoint))
        }
    }

    /// How much the image-pixel size of a stroke changes when the frame (and with it the display's
    /// pixel density) changes. Differing pixel densities across displays would otherwise make
    /// annotation strokes, text and mosaic blocks change visual size.
    static func imagePixelScaleRatio(
        from oldSelection: CGRect,
        oldImageSize: CGSize,
        to newSelection: CGRect,
        newImageSize: CGSize
    ) -> CGFloat {
        guard oldSelection.width > 0, newSelection.width > 0,
              oldImageSize.width > 0, newImageSize.width > 0 else { return 1 }
        let oldPixelsPerPoint = oldImageSize.width / oldSelection.width
        let newPixelsPerPoint = newImageSize.width / newSelection.width
        guard oldPixelsPerPoint > 0 else { return 1 }
        return newPixelsPerPoint / oldPixelsPerPoint
    }
}
