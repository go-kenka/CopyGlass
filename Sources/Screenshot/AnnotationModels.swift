import Foundation
import AppKit
import CoreGraphics

/// Tools available in the screenshot annotation editor.
enum AnnotationTool: String, CaseIterable, Identifiable, Codable {
    /// Pointer: select, move, resize, delete and re-edit existing annotations.
    case select
    case rectangle
    case ellipse
    case arrow
    case pen
    case highlighter
    case text
    case mosaic
    case number

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .text: return "character.cursor.ibeam"
        case .mosaic: return "squareshape.split.3x3"
        case .number: return "1.circle"
        }
    }

    var l10nKey: L10nKey {
        switch self {
        case .select: return .toolSelect
        case .rectangle: return .toolRectangle
        case .ellipse: return .toolEllipse
        case .arrow: return .toolArrow
        case .pen: return .toolPen
        case .highlighter: return .toolHighlighter
        case .text: return .toolText
        case .mosaic: return .toolMosaic
        case .number: return .toolNumber
        }
    }

    func title(_ lang: AppLanguage) -> String {
        L10n.t(l10nKey, lang: lang)
    }

    /// Tools that create a shape from a single drag between two points.
    var isTwoPointTool: Bool {
        switch self {
        case .rectangle, .ellipse, .arrow, .mosaic: return true
        case .select, .pen, .highlighter, .text, .number: return false
        }
    }

    /// Whether an existing shape of this kind can be resized through handles.
    var isResizable: Bool {
        switch self {
        case .rectangle, .ellipse, .arrow, .mosaic: return true
        case .select, .pen, .highlighter, .text, .number: return false
        }
    }
}

/// Codable color wrapper so annotations can be serialized later if needed.
struct AnnotationColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? NSColor.red
        self.red = Double(converted.redComponent)
        self.green = Double(converted.greenComponent)
        self.blue = Double(converted.blueComponent)
        self.alpha = Double(converted.alphaComponent)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    var cgColor: CGColor { nsColor.cgColor }

    func withAlpha(_ value: Double) -> AnnotationColor {
        AnnotationColor(red: red, green: green, blue: blue, alpha: value)
    }

    static let palette: [AnnotationColor] = [
        AnnotationColor(red: 1.00, green: 0.23, blue: 0.19),
        AnnotationColor(red: 1.00, green: 0.58, blue: 0.00),
        AnnotationColor(red: 1.00, green: 0.80, blue: 0.00),
        AnnotationColor(red: 0.20, green: 0.78, blue: 0.35),
        AnnotationColor(red: 0.00, green: 0.48, blue: 1.00),
        AnnotationColor(red: 0.69, green: 0.32, blue: 0.87),
        AnnotationColor(red: 0.10, green: 0.10, blue: 0.12),
        AnnotationColor(red: 1.00, green: 1.00, blue: 1.00)
    ]
}

/// A single annotation, with geometry stored in image pixel space (top-left origin).
struct AnnotationShape: Identifiable, Equatable {
    var id: UUID = UUID()
    var tool: AnnotationTool
    var points: [CGPoint]
    var color: AnnotationColor
    var lineWidth: CGFloat
    var text: String?
    var label: Int?
    /// Mosaic block size in image pixels.
    var blockSize: CGFloat = 14

    var bounds: CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }

    static func rectangle(from start: CGPoint, to end: CGPoint, color: AnnotationColor, lineWidth: CGFloat) -> AnnotationShape {
        AnnotationShape(tool: .rectangle, points: [start, end], color: color, lineWidth: lineWidth)
    }
}
