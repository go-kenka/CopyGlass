import Foundation
import AppKit
import SwiftUI

/// Hosts the SwiftUI screenshot editor inside a regular window.
final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    let model: ScreenshotEditorModel

    /// Called whenever the window goes away, no matter how it was closed.
    var onWindowClose: (() -> Void)?

    init(model: ScreenshotEditorModel, onClose: @escaping () -> Void) {
        self.model = model

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let imagePointSize = CGSize(
            width: CGFloat(model.originalImage.width) / scale,
            height: CGFloat(model.originalImage.height) / scale
        )
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(max(780, imagePointSize.width + 360), screenFrame.width * 0.92)
        let height = min(max(540, imagePointSize.height + 170), screenFrame.height * 0.92)

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t(.screenshotEditor, lang: AppLanguage.current)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 640, height: 420)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)
        window.center()

        let root = AppContainerView(content: ScreenshotEditorView(model: model, onClose: onClose))
        window.contentView = NSHostingView(rootView: root)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        onWindowClose?()
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// Keeps editor windows alive until the user closes them.
final class ScreenshotEditorManager {
    static let shared = ScreenshotEditorManager()

    private var controllers: [ScreenshotEditorWindowController] = []

    private init() {}

    var windowCount: Int { controllers.count }

    @discardableResult
    func present(image: CGImage, runOCR: Bool = false) -> ScreenshotEditorWindowController {
        let model = ScreenshotEditorModel(image: image)
        var controller: ScreenshotEditorWindowController!
        controller = ScreenshotEditorWindowController(model: model) { [weak controller] in
            controller?.window?.close()
        }
        controller.onWindowClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.present()
        if runOCR {
            model.recognizeText()
        }
        if ScreenshotDefaults.autoCopy {
            model.copyFlattenedToPasteboard()
        }
        return controller
    }
}
