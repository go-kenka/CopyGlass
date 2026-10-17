import AppKit
import SwiftUI

/// Dialog window for the quick reply editor.
///
/// The window deliberately has no close / minimize / zoom buttons: the form is dismissed with its
/// Cancel button (or Esc), so no traffic lights are rendered above it.
final class QuickReplyEditorWindow: NSWindow {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class QuickReplyEditorWindowController: NSWindowController {
    private let onSave: (QuickReplyItem) -> Void
    private let onCancel: () -> Void
    private var keyMonitor: Any?

    init(
        item: QuickReplyItem?,
        language: AppLanguage,
        onSave: @escaping (QuickReplyItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel

        let window = QuickReplyEditorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.onCancel = { [weak self] in self?.cancel() }
        // AppContainerView injects the app language and theme; without it the SwiftUI environment
        // falls back to English and the form's labels would not follow the app language.
        window.contentView = NSHostingView(rootView: AppContainerView(content: QuickReplyEditorView(
            item: item,
            lang: language,
            onSave: { [weak self] saved in self?.save(saved) },
            onCancel: { [weak self] in self?.cancel() }
        )))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func show(relativeTo parent: NSWindow?) {
        guard let window else { return }

        if let parent, parent.isVisible {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: parent.frame.midX - size.width / 2,
                y: parent.frame.midY - size.height / 2 + 24
            ))
            parent.addChildWindow(window, ordered: .above)
        } else {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
    }

    /// Dismisses the dialog without invoking any of the callbacks.
    func dismiss() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let window, let parent = window.parent {
            parent.removeChildWindow(window)
        }
        close()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 {
                // Let the input method cancel its composition before closing the dialog.
                if let textView = self.window?.firstResponder as? NSTextView, textView.hasMarkedText() {
                    return event
                }
                self.cancel()
                return nil
            }
            return event
        }
    }

    private func save(_ item: QuickReplyItem) {
        onSave(item)
        dismiss()
    }

    private func cancel() {
        onCancel()
        dismiss()
    }
}

/// Opens the add / edit quick reply dialog from AppKit code (the settings list lives inside the
/// SwiftUI window, but the dialog is its own window).
final class QuickReplyEditorPresenter {
    static let shared = QuickReplyEditorPresenter()

    private var controller: QuickReplyEditorWindowController?

    private init() {}

    func present(item: QuickReplyItem?, onSave: @escaping (QuickReplyItem) -> Void) {
        controller?.dismiss()
        let controller = QuickReplyEditorWindowController(
            item: item,
            language: L10n.currentLanguage,
            onSave: { [weak self] saved in
                self?.controller = nil
                onSave(saved)
            },
            onCancel: { [weak self] in
                self?.controller = nil
            }
        )
        self.controller = controller
        controller.show(relativeTo: mainWindow)
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == MainWindow.sceneID }
    }
}
