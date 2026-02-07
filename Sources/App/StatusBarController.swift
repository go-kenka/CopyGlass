import AppKit
import SwiftUI
import Carbon

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var windowController: NSWindowController?
    private var historyPaletteController: NSWindowController?
    private var quickReplyPaletteController: NSWindowController?
    private var clipboardManager: ClipboardManager
    private let quickReplyStore = QuickReplyStore.shared
    private let hotKeySettings = HotKeySettingsStore.shared
    private let historyPaletteModel = HistoryPaletteModel()
    private let quickReplyPaletteModel = QuickReplyPaletteModel()
    
    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        clipboardManager = ClipboardManager()
        super.init()
        
        clipboardManager.startMonitoring()
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "CopyGlass")
        }
        setupMenu()
        setupHotKey()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadHotKeys), name: .hotKeySettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadMenu), name: UserDefaults.didChangeNotification, object: nil)
    }
    
    private func setupMenu() {
        let lang = currentAppLanguage()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.t(.showMainWindow, lang: lang), action: #selector(showHistory), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.t(.quit, lang: lang), action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        
        menu.items.forEach { $0.target = self }
    }

    @objc private func reloadMenu() {
        setupMenu()
    }

    private func currentAppLanguage() -> AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.zhHans.rawValue
        return AppLanguage(rawValue: raw) ?? .zhHans
    }
    
    private func setupHotKey() {
        applyHotKeys()
    }
    
    @objc private func reloadHotKeys() {
        applyHotKeys()
    }
    
    private func applyHotKeys() {
        HotKeyManager.shared.unregisterAll()
        
        let toggleMain = hotKeySettings.binding(for: .toggleMainWindow)
        HotKeyManager.shared.registerHotKey(
            id: HotKeyAction.toggleMainWindow.registrationID,
            keyCode: toggleMain.keyCode,
            modifiers: toggleMain.modifiers
        ) { [weak self] in
            DispatchQueue.main.async { self?.toggleHistory() }
        }
        
        let historyPalette = hotKeySettings.binding(for: .showHistoryPalette)
        HotKeyManager.shared.registerHotKey(
            id: HotKeyAction.showHistoryPalette.registrationID,
            keyCode: historyPalette.keyCode,
            modifiers: historyPalette.modifiers
        ) { [weak self] in
            DispatchQueue.main.async { self?.toggleHistoryPalette() }
        }
        
        let quickReplyPalette = hotKeySettings.binding(for: .showQuickReplyPalette)
        HotKeyManager.shared.registerHotKey(
            id: HotKeyAction.showQuickReplyPalette.registrationID,
            keyCode: quickReplyPalette.keyCode,
            modifiers: quickReplyPalette.modifiers
        ) { [weak self] in
            DispatchQueue.main.async { self?.toggleQuickReplyPalette() }
        }
    }
    
    @objc func toggleHistory() {
        if let window = windowController?.window, window.isVisible {
            window.orderOut(nil)
        } else {
            showHistory()
        }
    }
    
    @objc func showHistory() {
        if windowController == nil {
            let contentView = AppContainerView(content: SettingsView(clipboardManager: clipboardManager))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            
            window.title = "CopyGlass"
            window.center()
            window.setFrameAutosaveName("Main Window v2")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: contentView)
            
            // Glass effect configuration
            window.backgroundColor = .clear
            window.isOpaque = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            
            // Enable clicking background to move window
            window.isMovableByWindowBackground = true
            
            windowController = NSWindowController(window: window)
        }
        
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func toggleHistoryPalette() {
        if let window = historyPaletteController?.window, window.isVisible {
            window.orderOut(nil)
        } else {
            showHistoryPalette()
        }
    }
    
    @objc func toggleQuickReplyPalette() {
        if let window = quickReplyPaletteController?.window, window.isVisible {
            window.orderOut(nil)
        } else {
            showQuickReplyPalette()
        }
    }
    
    private func showHistoryPalette() {
        // 捕获当前活跃的应用
        PasteboardHelper.captureActiveApp()

        if historyPaletteController == nil {
            let contentView = AppContainerView(content: HistoryPaletteView(
                clipboardManager: clipboardManager,
                model: historyPaletteModel,
                onPick: { [weak self] id in
                    if let item = ClipboardItemStore.shared.fetch(id: id) {
                        self?.clipboardManager.copyToPasteboard(item: item)
                        PasteboardHelper.showCopySuccessToast()
                        self?.historyPaletteController?.window?.orderOut(nil)
                        PasteboardHelper.restoreAndPaste()
                    }
                },
                onCancel: { [weak self] in
                    self?.historyPaletteController?.window?.orderOut(nil)
                }
            ))
            let panel = makePalettePanel(rootView: contentView)
            let controller = PaletteWindowController(window: panel)
            controller.keyHandler = { [weak self] event in
                self?.handleHistoryPaletteKey(event) ?? false
            }
            historyPaletteController = controller
        }
        historyPaletteModel.resetSelectionToFirst()
        showPalette(historyPaletteController)
    }
    
    private func showQuickReplyPalette() {
        // 捕获当前活跃的应用
        PasteboardHelper.captureActiveApp()

        if quickReplyPaletteController == nil {
            let contentView = AppContainerView(content: QuickReplyPaletteView(
                store: quickReplyStore,
                model: quickReplyPaletteModel,
                onPick: { [weak self] item in
                    self?.quickReplyStore.copyToPasteboard(item)
                    PasteboardHelper.showCopySuccessToast()
                    self?.quickReplyPaletteController?.window?.orderOut(nil)
                    PasteboardHelper.restoreAndPaste()
                },
                onCancel: { [weak self] in
                    self?.quickReplyPaletteController?.window?.orderOut(nil)
                }
            ))
            let panel = makePalettePanel(rootView: contentView)
            let controller = PaletteWindowController(window: panel)
            controller.keyHandler = { [weak self] event in
                self?.handleQuickReplyPaletteKey(event) ?? false
            }
            quickReplyPaletteController = controller
        }
        showPalette(quickReplyPaletteController)
    }
    
    private func handleHistoryPaletteKey(_ event: NSEvent) -> Bool {
        if shouldIgnoreSubmitKey(event, window: historyPaletteController?.window) {
            return false
        }
        switch Int(event.keyCode) {
        case 125:
            historyPaletteModel.moveSelection(delta: 1)
            return true
        case 126:
            historyPaletteModel.moveSelection(delta: -1)
            return true
        case 36, 76:
            guard let id = historyPaletteModel.selectedID else { return true }
            if let item = ClipboardItemStore.shared.fetch(id: id) {
                clipboardManager.copyToPasteboard(item: item)
                PasteboardHelper.showCopySuccessToast()
                historyPaletteController?.window?.orderOut(nil)
                PasteboardHelper.restoreAndPaste()
            }
            return true
        case 53:
            historyPaletteController?.window?.orderOut(nil)
            return true
        default:
            return false
        }
    }
    
    private func handleQuickReplyPaletteKey(_ event: NSEvent) -> Bool {
        if shouldIgnoreSubmitKey(event, window: quickReplyPaletteController?.window) {
            return false
        }
        switch Int(event.keyCode) {
        case 125:
            quickReplyPaletteModel.moveSelection(delta: 1)
            return true
        case 126:
            quickReplyPaletteModel.moveSelection(delta: -1)
            return true
        case 36, 76:
            guard let id = quickReplyPaletteModel.selectedID else { return true }
            if let item = quickReplyPaletteModel.items.first(where: { $0.id == id }) ?? QuickReplyItemStore.shared.fetch(id: id) {
                quickReplyStore.copyToPasteboard(item)
                PasteboardHelper.showCopySuccessToast()
                quickReplyPaletteController?.window?.orderOut(nil)
                PasteboardHelper.restoreAndPaste()
            }
            return true
        case 53:
            quickReplyPaletteController?.window?.orderOut(nil)
            return true
        default:
            return false
        }
    }
    
    private func shouldIgnoreSubmitKey(_ event: NSEvent, window: NSWindow?) -> Bool {
        let keyCode = Int(event.keyCode)
        guard keyCode == 36 || keyCode == 76 else { return false }
        guard let textView = window?.firstResponder as? NSTextView, textView.isFieldEditor else { return false }
        if textView.hasMarkedText() { return true }
        return true
    }
    
    private func showPalette(_ controller: NSWindowController?) {
        controller?.showWindow(nil)
        controller?.window?.center()
        controller?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func makePalettePanel<Content: View>(rootView: Content) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = NSHostingView(rootView: rootView)
        return panel
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
