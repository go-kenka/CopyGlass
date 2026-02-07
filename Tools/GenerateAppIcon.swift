import AppKit

struct AppIconStyle {
    let startColor: NSColor
    let endColor: NSColor
    let symbolColor: NSColor
    let symbolSecondary: NSColor
    
    static let copyGlass = AppIconStyle(
        startColor: NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.98, alpha: 1.0),
        endColor: NSColor(calibratedRed: 0.33, green: 0.35, blue: 0.92, alpha: 1.0),
        symbolColor: NSColor(white: 1.0, alpha: 0.92),
        symbolSecondary: NSColor(white: 1.0, alpha: 0.55)
    )
}

func squirclePath(in rect: CGRect) -> CGPath {
    let r = min(rect.width, rect.height)
    let radius = r * 0.223
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func roundedRectPath(in rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawBackground(in ctx: CGContext, rect: CGRect, style: AppIconStyle) {
    ctx.saveGState()
    let clipPath = squirclePath(in: rect)
    ctx.addPath(clipPath)
    ctx.clip()
    
    let colors = [style.startColor.cgColor, style.endColor.cgColor] as CFArray
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    
    let sheen = CGGradient(
        colorsSpace: colorSpace,
        colors: [NSColor(white: 1.0, alpha: 0.35).cgColor, NSColor(white: 1.0, alpha: 0.0).cgColor] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY),
        options: []
    )
    
    ctx.restoreGState()
}

func drawClipboard(in ctx: CGContext, rect: CGRect, style: AppIconStyle) {
    let r = min(rect.width, rect.height)
    let bodyInset = r * 0.22
    let bodyRect = rect.insetBy(dx: bodyInset, dy: bodyInset * 0.92)
    let bodyRadius = r * 0.085
    
    ctx.saveGState()
    
    ctx.setShadow(offset: CGSize(width: 0, height: -r * 0.012), blur: r * 0.03, color: NSColor(white: 0.0, alpha: 0.18).cgColor)
    ctx.addPath(roundedRectPath(in: bodyRect, radius: bodyRadius))
    ctx.setFillColor(style.symbolColor.cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    
    let topWidth = bodyRect.width * 0.58
    let topHeight = bodyRect.height * 0.16
    let topRect = CGRect(
        x: bodyRect.midX - topWidth / 2,
        y: bodyRect.maxY - topHeight * 0.72,
        width: topWidth,
        height: topHeight
    )
    let topRadius = topHeight * 0.55
    ctx.addPath(roundedRectPath(in: topRect, radius: topRadius))
    ctx.setFillColor(style.symbolSecondary.cgColor)
    ctx.fillPath()
    
    let lineCount = 3
    let lineLeft = bodyRect.minX + bodyRect.width * 0.14
    let lineRight = bodyRect.maxX - bodyRect.width * 0.14
    let lineWidth = lineRight - lineLeft
    let lineHeight = max(1.0, r * 0.028)
    let lineGap = r * 0.07
    let startY = bodyRect.midY + lineGap * 0.45
    
    ctx.setFillColor(NSColor(calibratedWhite: 0.0, alpha: 0.10).cgColor)
    for i in 0..<lineCount {
        let wFactor: CGFloat = i == 2 ? 0.62 : 0.88
        let lineRect = CGRect(
            x: lineLeft,
            y: startY - CGFloat(i) * lineGap,
            width: lineWidth * wFactor,
            height: lineHeight
        )
        ctx.addPath(roundedRectPath(in: lineRect, radius: lineHeight / 2))
        ctx.fillPath()
    }
    
    ctx.restoreGState()
}

func renderIcon(pixels: Int, style: AppIconStyle) -> NSImage {
    let size = CGSize(width: pixels, height: pixels)
    let img = NSImage(size: size)
    img.lockFocusFlipped(false)
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    
    let rect = CGRect(origin: .zero, size: size)
    drawBackground(in: ctx, rect: rect, style: style)
    drawClipboard(in: ctx, rect: rect, style: style)
    
    img.unlockFocus()
    return img
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateAppIcon", code: 1)
    }
    try png.write(to: url, options: [.atomic])
}

func main() throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: fm.currentDirectoryPath)
    let outDir = root.appendingPathComponent("CopyGlass/Sources/Resources/AppIcon.iconset", isDirectory: true)
    try? fm.removeItem(at: outDir)
    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
    
    let style = AppIconStyle.copyGlass
    let pairs: [(base: Int, scale: Int)] = [
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2)
    ]
    
    for (base, scale) in pairs {
        let px = base * scale
        let image = renderIcon(pixels: px, style: style)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@\(scale)x.png"
        try writePNG(image, to: outDir.appendingPathComponent(name))
    }
    
    print("Wrote iconset to \(outDir.path)")
}

try main()

