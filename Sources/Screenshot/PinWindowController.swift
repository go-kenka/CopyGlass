import Foundation
import AppKit
import CoreGraphics

/// Manages floating always-on-top screenshot windows ("pin to screen").
final class PinWindowManager {
    static let shared = PinWindowManager()

    private var controllers: [PinWindowController] = []

    var count: Int { controllers.count }

    private init() {}

    @discardableResult
    func pin(image: CGImage, at cocoaPoint: CGPoint? = nil) -> PinWindowController? {
        let controller = PinWindowController(image: image)
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.show(at: cocoaPoint)
        return controller
    }

    func unpinAll() {
        let all = controllers
        controllers.removeAll()
        all.forEach { $0.close() }
    }
}

final class PinWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    let image: CGImage
    private var imageView: PinnedImageView?
    private var opacity: CGFloat = 1.0

    init(image: CGImage) {
        self.image = image
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pointSize = CGSize(
            width: max(40, CGFloat(image.width) / scale),
            height: max(40, CGFloat(image.height) / scale)
        )
        let panel = PinPanel(
            contentRect: CGRect(origin: .zero, size: pointSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        super.init(window: panel)

        let view = PinnedImageView(frame: CGRect(origin: .zero, size: pointSize), image: image)
        view.autoresizingMask = [.width, .height]
        view.controller = self
        panel.contentView = view
        imageView = view
        panel.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func show(at cocoaPoint: CGPoint?) {
        guard let window else { return }
        if let point = cocoaPoint {
            var origin = CGPoint(x: point.x - window.frame.width / 2, y: point.y - window.frame.height / 2)
            if let frame = ScreenGeometry.screen(containing: point)?.frame {
                origin.x = min(max(origin.x, frame.minX), max(frame.minX, frame.maxX - window.frame.width))
                origin.y = min(max(origin.y, frame.minY), max(frame.minY, frame.maxY - window.frame.height))
            }
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
        window.alphaValue = opacity
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    override func close() {
        let handler = onClose
        onClose = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        handler?()
    }

    func setOpacity(_ value: CGFloat) {
        opacity = max(0.15, min(1.0, value))
        window?.alphaValue = opacity
    }

    func copyImageToPasteboard() {
        ScreenshotClipboard.copy(image: image)
        imageView?.flashFeedback(L10n.t(.copied, lang: AppLanguage.current))
    }

    func saveImage() {
        ScreenshotSaver.save(image: image, suggestedName: nil, window: window)
    }

    func extractText() {
        imageView?.flashFeedback(L10n.t(.ocrRecognizing, lang: AppLanguage.current))
        let image = self.image
        Task {
            let result = await OCRService.recognizeAsync(image: image)
            await MainActor.run {
                switch result {
                case .success(let ocr) where !ocr.plainText.isEmpty:
                    ScreenshotClipboard.copy(text: ocr.plainText)
                    self.imageView?.flashFeedback(L10n.t(.copied, lang: AppLanguage.current))
                case .success:
                    self.imageView?.flashFeedback(L10n.t(.ocrEmpty, lang: AppLanguage.current))
                case .failure:
                    self.imageView?.flashFeedback(L10n.t(.ocrEmpty, lang: AppLanguage.current))
                }
            }
        }
    }

    /// Resizes the pinned window, keeping the image aspect ratio and the top-left corner anchored.
    func resize(toPointSize size: CGSize, topLeftAnchor anchor: CGPoint) {
        guard let window else { return }
        let ratio = max(0.05, CGFloat(image.width) / CGFloat(image.height))
        var width = max(60, size.width)
        var height = width / ratio
        if height < 60 {
            height = 60
            width = height * ratio
        }
        let frame = CGRect(x: anchor.x, y: anchor.y - height, width: width, height: height)
        window.setFrame(frame, display: true)
    }

    func resetToOriginalSize() {
        guard let window else { return }
        let scale = window.screen?.backingScaleFactor ?? 2
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        var frame = window.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        window.setFrame(frame, display: true)
    }

    @objc func contextCopy() { copyImageToPasteboard() }
    @objc func contextSave() { saveImage() }
    @objc func contextOCR() { extractText() }
    @objc func contextClose() { close() }
    @objc func contextResetSize() { resetToOriginalSize() }
    @objc func contextCloseAll() { PinWindowManager.shared.unpinAll() }

    @objc func contextOpacity(_ sender: NSMenuItem) {
        setOpacity(CGFloat(sender.tag) / 100.0)
    }

    func makeContextMenu() -> NSMenu {
        let lang = AppLanguage.current
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.t(.copy, lang: lang), action: #selector(contextCopy), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t(.save, lang: lang), action: #selector(contextSave), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t(.ocrTitle, lang: lang), action: #selector(contextOCR), keyEquivalent: "").target = self
        menu.addItem(.separator())

        let opacityItem = NSMenuItem(title: L10n.t(.pinOpacity, lang: lang), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in [100, 75, 50, 30] {
            let item = NSMenuItem(title: String(value) + "%", action: #selector(contextOpacity(_:)), keyEquivalent: "")
            item.tag = value
            item.target = self
            submenu.addItem(item)
        }
        opacityItem.submenu = submenu
        menu.addItem(opacityItem)

        menu.addItem(withTitle: L10n.t(.pinResizeToOriginal, lang: lang), action: #selector(contextResetSize), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t(.close, lang: lang), action: #selector(contextClose), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t(.pinUnpinAll, lang: lang), action: #selector(contextCloseAll), keyEquivalent: "").target = self
        return menu
    }
}

final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws the pinned image and hosts the hover toolbar plus the resize grip.
final class PinnedImageView: NSView {
    weak var controller: PinWindowController?
    private let image: CGImage
    private var trackingArea: NSTrackingArea?
    private var toolbar: NSStackView?
    private var feedbackLabel: NSTextField?
    private var isResizing = false
    private var resizeAnchor: CGPoint = .zero
    private var feedbackTimer: Timer?

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private var gripRect: CGRect {
        CGRect(x: bounds.maxX - 16, y: bounds.minY, width: 16, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        AnnotationRenderer.drawUpright(image, in: bounds, context: context)
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setFillColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        for index in 0..<3 {
            let inset = CGFloat(index) * 4 + 3
            let rect = CGRect(x: bounds.maxX - inset, y: bounds.minY + inset - 2, width: 2.5, height: 2.5)
            context.fill(rect)
        }
        context.restoreGState()
    }

    override func mouseEntered(with event: NSEvent) { showToolbar(true) }
    override func mouseExited(with event: NSEvent) { showToolbar(false) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if gripRect.contains(point) {
            isResizing = true
            if let window {
                resizeAnchor = CGPoint(x: window.frame.minX, y: window.frame.maxY)
            }
            return
        }
        if event.clickCount == 2 {
            controller?.copyImageToPasteboard()
            return
        }
        window?.performDrag(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizing else { return }
        let point = NSEvent.mouseLocation
        let size = CGSize(width: point.x - resizeAnchor.x, height: resizeAnchor.y - point.y)
        controller?.resize(toPointSize: size, topLeftAnchor: resizeAnchor)
    }

    override func mouseUp(with event: NSEvent) {
        isResizing = false
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.makeContextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53:
            controller?.close()
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
                controller?.copyImageToPasteboard()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: Toolbar

    private func showToolbar(_ visible: Bool) {
        if visible, toolbar == nil { buildToolbar() }
        toolbar?.isHidden = !visible
    }

    private func buildToolbar() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        stack.layer?.cornerRadius = 8

        let buttons: [(String, Selector)] = [
            ("doc.on.doc", #selector(toolbarCopy)),
            ("square.and.arrow.down", #selector(toolbarSave)),
            ("text.viewfinder", #selector(toolbarOCR)),
            ("xmark", #selector(toolbarClose))
        ]
        for (symbol, selector) in buttons {
            let button = NSButton()
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = .white
            button.target = self
            button.action = selector
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            stack.addArrangedSubview(button)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8)
        ])
        toolbar = stack
    }

    @objc private func toolbarCopy() { controller?.copyImageToPasteboard() }
    @objc private func toolbarSave() { controller?.saveImage() }
    @objc private func toolbarOCR() { controller?.extractText() }
    @objc private func toolbarClose() { controller?.close() }

    func flashFeedback(_ text: String) {
        feedbackTimer?.invalidate()
        let label: NSTextField
        if let existing = feedbackLabel {
            label = existing
        } else {
            let created = NSTextField(labelWithString: "")
            created.font = .systemFont(ofSize: 12, weight: .semibold)
            created.textColor = .white
            created.alignment = .center
            created.wantsLayer = true
            created.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
            created.layer?.cornerRadius = 8
            addSubview(created)
            feedbackLabel = created
            label = created
        }
        label.stringValue = "  " + text + "  "
        label.sizeToFit()
        label.frame = CGRect(
            x: bounds.midX - label.frame.width / 2,
            y: bounds.midY - 14,
            width: label.frame.width,
            height: 28
        )
        label.isHidden = false
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            self?.feedbackLabel?.isHidden = true
        }
    }
}
