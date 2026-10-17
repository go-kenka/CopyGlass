import Foundation
import AppKit
import CoreGraphics

/// A grab point on a selected annotation.
enum AnnotationHandle: Hashable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    /// Arrow endpoints.
    case start, end
}

/// What pressing the mouse on the capture should start.
enum AnnotationPressIntent: Equatable {
    case resize(id: UUID, handle: AnnotationHandle)
    /// A single click on a text annotation opens it for typing.
    case editText(id: UUID)
    case move(id: UUID)
    case draw
    case none
}

/// Hit testing and geometry for re-editing existing annotations. Everything works in image pixel
/// space (top-left origin), the same space the shapes are stored in.
enum AnnotationHitTester {
    /// Decides what a press starts: handles win over shapes, a text annotation opens on a click
    /// (dragging it still moves it), and Option always draws a new shape on top.
    static func pressIntent(
        at imagePoint: CGPoint,
        shapes: [AnnotationShape],
        selected: AnnotationShape?,
        tool: AnnotationTool,
        optionHeld: Bool,
        screenScale: CGFloat
    ) -> AnnotationPressIntent {
        let handleTolerance = 9 / max(screenScale, 0.01)

        guard !optionHeld else {
            return tool == .select ? .none : .draw
        }

        if let selected,
           let handle = handle(at: imagePoint, for: selected, tolerance: handleTolerance) {
            return .resize(id: selected.id, handle: handle)
        }

        if let hit = hitTest(shapes, imagePoint: imagePoint) {
            return hit.tool == .text ? .editText(id: hit.id) : .move(id: hit.id)
        }

        return tool == .select ? .none : .draw
    }

    /// How far outside a shape a click still counts, in image pixels.
    static func tolerance(forLineWidth lineWidth: CGFloat) -> CGFloat {
        max(6, lineWidth * 1.5)
    }

    /// The area a shape occupies, including its stroke width.
    static func displayBounds(for shape: AnnotationShape) -> CGRect {
        switch shape.tool {
        case .number:
            guard let centre = shape.points.first else { return .zero }
            let radius = max(14, shape.lineWidth * 5)
            return CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
        case .text:
            return AnnotationRenderer.textBounds(for: shape) ?? .zero
        case .pen, .highlighter:
            return shape.bounds.insetBy(dx: -shape.lineWidth * 1.5, dy: -shape.lineWidth * 1.5)
        case .select:
            return .zero
        default:
            return shape.bounds
        }
    }

    static func contains(_ shape: AnnotationShape, imagePoint point: CGPoint, tolerance: CGFloat? = nil) -> Bool {
        let slack = tolerance ?? Self.tolerance(forLineWidth: shape.lineWidth)
        switch shape.tool {
        case .select:
            return false

        case .rectangle, .mosaic:
            let rect = shape.bounds
            guard rect.width > 0 || rect.height > 0 else { return false }
            return rect.insetBy(dx: -slack, dy: -slack).contains(point)

        case .ellipse:
            let rect = shape.bounds
            guard rect.width > 0, rect.height > 0 else { return false }
            let rx = rect.width / 2 + slack
            let ry = rect.height / 2 + slack
            let dx = (point.x - rect.midX) / rx
            let dy = (point.y - rect.midY) / ry
            return dx * dx + dy * dy <= 1

        case .arrow:
            guard let start = shape.points.first, let end = shape.points.last, shape.points.count >= 2 else { return false }
            return distance(from: point, toSegment: start, end) <= slack

        case .pen, .highlighter:
            guard let first = shape.points.first else { return false }
            guard shape.points.count >= 2 else {
                return hypot(point.x - first.x, point.y - first.y) <= slack
            }
            for index in 0..<(shape.points.count - 1) {
                if distance(from: point, toSegment: shape.points[index], shape.points[index + 1]) <= slack {
                    return true
                }
            }
            return false

        case .text:
            guard let bounds = AnnotationRenderer.textBounds(for: shape) else { return false }
            return bounds.insetBy(dx: -slack, dy: -slack).contains(point)

        case .number:
            guard let centre = shape.points.first else { return false }
            let radius = max(14, shape.lineWidth * 5) + slack
            return hypot(point.x - centre.x, point.y - centre.y) <= radius
        }
    }

    /// Topmost shape under the point.
    static func hitTest(_ shapes: [AnnotationShape], imagePoint point: CGPoint) -> AnnotationShape? {
        for shape in shapes.reversed() where contains(shape, imagePoint: point) {
            return shape
        }
        return nil
    }

    // MARK: - Handles

    static func handles(for shape: AnnotationShape) -> [(handle: AnnotationHandle, point: CGPoint)] {
        guard shape.tool.isResizable else { return [] }
        if shape.tool == .arrow {
            guard let start = shape.points.first, let end = shape.points.last, shape.points.count >= 2 else { return [] }
            return [(.start, start), (.end, end)]
        }
        let rect = shape.bounds
        return [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY))
        ]
    }

    static func handle(
        at imagePoint: CGPoint,
        for shape: AnnotationShape,
        tolerance: CGFloat
    ) -> AnnotationHandle? {
        for (handle, point) in handles(for: shape) {
            if hypot(point.x - imagePoint.x, point.y - imagePoint.y) <= tolerance {
                return handle
            }
        }
        return nil
    }

    // MARK: - Transformations

    static func translate(_ shape: AnnotationShape, by delta: CGSize) -> AnnotationShape {
        var result = shape
        result.points = shape.points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
        return result
    }

    static func resize(_ shape: AnnotationShape, handle: AnnotationHandle, to point: CGPoint) -> AnnotationShape {
        var result = shape
        switch shape.tool {
        case .arrow:
            guard shape.points.count >= 2 else { return shape }
            if handle == .start {
                result.points[0] = point
            } else if handle == .end {
                result.points[shape.points.count - 1] = point
            }
            return result

        default:
            var rect = shape.bounds
            switch handle {
            case .topLeft:
                rect = CGRect(x: point.x, y: point.y, width: rect.maxX - point.x, height: rect.maxY - point.y)
            case .top:
                rect = CGRect(x: rect.minX, y: point.y, width: rect.width, height: rect.maxY - point.y)
            case .topRight:
                rect = CGRect(x: rect.minX, y: point.y, width: point.x - rect.minX, height: rect.maxY - point.y)
            case .right:
                rect = CGRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: rect.height)
            case .bottomRight:
                rect = CGRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: point.y - rect.minY)
            case .bottom:
                rect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: point.y - rect.minY)
            case .bottomLeft:
                rect = CGRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: point.y - rect.minY)
            case .left:
                rect = CGRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: rect.height)
            case .start, .end:
                return shape
            }
            result.points = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY)
            ]
            return result
        }
    }

    // MARK: - Geometry helpers

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}
