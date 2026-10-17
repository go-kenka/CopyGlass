import Foundation
import AppKit
import CoreGraphics

/// Supported on-disk / clipboard image formats for screenshots.
enum ScreenshotImageFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case tiff

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        }
    }

    var bitmapFileType: NSBitmapImageRep.FileType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        }
    }
}

/// Small collection of CoreGraphics helpers shared by the screenshot pipeline.
enum ImageUtils {
    static let deviceRGB = CGColorSpaceCreateDeviceRGB()
    static let bitmapInfo: UInt32 =
        CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: deviceRGB,
            bitmapInfo: bitmapInfo
        )
    }

    /// Crops an image with a rectangle expressed in the image's top-left origin pixel space.
    ///
    /// The semantics of CGImage.cropping(to:) are easy to get wrong across flipped contexts, so the
    /// crop is performed by redrawing the image with an offset into a context of the target size.
    static func crop(_ image: CGImage, topLeftRect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = topLeftRect.standardized
        let clipped = rect.integral.intersection(bounds)
        guard clipped.width >= 1, clipped.height >= 1 else { return nil }
        guard let context = makeContext(width: Int(clipped.width), height: Int(clipped.height)) else { return nil }
        context.interpolationQuality = .none
        let offsetY = CGFloat(image.height) - clipped.maxY
        context.draw(image, in: CGRect(
            x: -clipped.minX,
            y: -offsetY,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        ))
        return context.makeImage()
    }

    static func encode(_ image: CGImage, format: ScreenshotImageFormat, quality: Double = 0.9) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        switch format {
        case .png:
            return rep.representation(using: .png, properties: [:])
        case .tiff:
            return rep.representation(using: .tiff, properties: [:])
        case .jpeg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: max(0.1, min(1.0, quality))])
        }
    }

    static func nsImage(from image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
