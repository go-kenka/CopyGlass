import AppKit
import CoreGraphics

/// Fits a stitched long image into the visible screen area for the in-place capture editor.
///
/// The image is placed where a normal capture frame would be: centred on the screen, never upscaled
/// past 1:1 points, with room kept underneath for the floating capture toolbar.
enum LongImageEditorLayout {
    /// Space kept free under the image for the floating capture toolbar.
    static let toolbarRoom: CGFloat = 96
    /// Margin around the image.
    static let margin: CGFloat = 24

    static func fittedSelection(
        imagePixelSize: CGSize,
        visibleFrame: CGRect,
        backingScale: CGFloat
    ) -> CGRect {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0,
              visibleFrame.width > 0, visibleFrame.height > 0 else { return .zero }

        let availableWidth = max(80, visibleFrame.width - margin * 2)
        let availableHeight = max(80, visibleFrame.height - toolbarRoom - margin * 2)
        let oneToOne = 1 / max(backingScale, 1)
        let scale = min(oneToOne, availableWidth / imagePixelSize.width, availableHeight / imagePixelSize.height)
        let size = CGSize(
            width: (imagePixelSize.width * scale).rounded(.down),
            height: (imagePixelSize.height * scale).rounded(.down)
        )
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + toolbarRoom + margin + (availableHeight - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }
}
