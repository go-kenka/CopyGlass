import Foundation
import AppKit
import SwiftUI
import CoreGraphics
import QuartzCore
import Carbon
import Combine

/// Full-screen frozen overlay driving a capture:
///
/// * selection phase — the window under the cursor is highlighted first (click captures it) and
///   dragging selects a free region;
/// * editing phase — Feishu-style in-place annotation over the frozen pixels with a floating
///   toolbar under the capture (draw, mosaic, text, step numbers, extract text, pin, save, copy).
final class RegionSelectionController {
    struct SelectionResult {
        /// Selection in Cocoa global coordinates (bottom-left origin).
        let cocoaRect: CGRect
        let windowID: CGWindowID?
        let windowTitle: String?
    }

    enum Mode {
        /// Window-first: hover highlights a window, click captures it, drag selects a region.
        case region
        /// Window only: dragging is disabled.
        case window
    }

    enum Purpose {
        case edit
        case scroll
        case extractText
    }

    enum Phase {
        case selecting
        case editing
    }

    static let shared = RegionSelectionController()

    private(set) var isActive = false
    private(set) var phase: Phase = .selecting
    private(set) var session: CaptureSession?
    private(set) var selection: CGRect = .zero
    private(set) var cursorPoint: CGPoint = .zero
    private(set) var hoveredWindow: CapturableWindow?
    private(set) var mode: Mode = .region
    private(set) var purpose: Purpose = .edit

    private var windows: [SelectionOverlayWindow] = []
    /// Overlay windows per display. They are created and ordered in (invisible and click-through)
    /// before the capture starts, so the window server has already mapped them when the frozen
    /// frame is ready — a freshly ordered full-screen window needs several frames to appear, and
    /// during those frames the live desktop would still be visible.
    private var overlayWindows: [CGDirectDisplayID: SelectionOverlayWindow] = [:]
    private var images: [CGDirectDisplayID: CGImage] = [:]
    private var candidates: [CapturableWindow] = []
    private var completion: ((SelectionResult?) -> Void)?
    private var keyMonitor: Any?
    private var dragOrigin: CGPoint?
    private var dragMoved = false
    private var previousApp: NSRunningApplication?
    private var preselectRect: CGRect?
    private var toolbarHost: NSView?
    private var sessionObserver: AnyCancellable?
    private var activationWorkItem: DispatchWorkItem?
    private var focusRestoreObserver: NSObjectProtocol?
    private var pendingTeardown: (() -> Void)?
    /// A capture-frame drag in flight: a handle resize (`handle != nil`) or a move (`handle == nil`).
    private var frameDrag: FrameDrag?

    private struct FrameDrag {
        let startSelection: CGRect
        let startPoint: CGPoint
        let handle: SelectionHandle?
    }

    private init() {}

    var hintText: String {
        let lang = AppLanguage.current
        switch phase {
        case .editing:
            return L10n.t(.selectionHintEditing, lang: lang)
        case .selecting:
            return mode == .window
                ? L10n.t(.selectionHintWindow, lang: lang)
                : L10n.t(.selectionHintRegion, lang: lang)
        }
    }

    var hoveredWindowLabel: String {
        guard let hovered = hoveredWindow else { return "" }
        let scale = ScreenGeometry.screen(bestMatching: hovered.cocoaFrame)?.backingScaleFactor ?? 2
        let width = Int((hovered.cocoaFrame.width * scale).rounded())
        let height = Int((hovered.cocoaFrame.height * scale).rounded())
        var label = hovered.title.isEmpty ? hovered.ownerName : "\(hovered.ownerName) — \(hovered.title)"
        if label.count > 48 {
            label = String(label.prefix(48)) + "…"
        }
        return "\(label)  \(width) x \(height)"
    }

    func hoveredRectLocal(to screen: NSScreen) -> CGRect? {
        guard let hovered = hoveredWindow else { return nil }
        let intersection = hovered.cocoaFrame.intersection(screen.frame)
        guard !intersection.isNull else { return nil }
        return intersection.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    // MARK: - Lifecycle

    /// - Parameter preselect: skips the selection phase for this Cocoa-global rectangle (used by
    ///   full screen capture).
    func begin(
        mode: Mode = .region,
        purpose: Purpose = .edit,
        preselect: CGRect? = nil,
        onError: @escaping (Error) -> Void,
        completion: ((SelectionResult?) -> Void)? = nil
    ) {
        guard !isActive else { return }
        // A previous teardown may still be waiting for the other app to regain focus; it must not
        // close the windows of the capture that is about to start.
        finishPendingTeardownIfNeeded()
        // Give the recognition models and the capture pipeline a head start.
        OCRService.warmUpIfNeeded()
        ScreenCaptureService.shared.warmUp()
        isActive = true
        self.mode = mode
        self.purpose = purpose
        self.preselectRect = preselect
        self.completion = completion
        phase = .selecting
        session = nil
        selection = .zero
        hoveredWindow = nil
        dragOrigin = nil
        dragMoved = false
        cursorPoint = NSEvent.mouseLocation

        // Lay the overlay windows down before the capture runs. They are fully transparent and
        // click-through at this point; mapping them now means the frozen frame can be revealed on
        // the next refresh instead of leaving the live desktop visible while a fresh window maps.
        prepareOverlayWindows()

        Task {
            do {
                let captured = try await ScreenCaptureService.shared.captureAllDisplays()
                await MainActor.run {
                    self.present(images: captured)
                }
            } catch {
                await MainActor.run {
                    self.teardown()
                    onError(error)
                }
            }
        }
    }

    private func present(images: [CGDirectDisplayID: CGImage]) {
        guard isActive else { return }
        self.images = images
        previousApp = NSWorkspace.shared.frontmostApplication
        candidates = WindowHitTester.candidates()
        // Window-first: highlight whatever is under the cursor right away.
        hoveredWindow = WindowHitTester.window(at: cursorPoint, in: candidates)

        // Refresh the pre-warmed windows for the displays that were captured. The frames are drawn
        // while the windows are still transparent; the window server picks the frozen image up with
        // the reveal below, so it never composites an empty overlay over the live desktop.
        var ready: [SelectionOverlayWindow] = []
        var readyDisplayIDs: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID, let image = images[displayID],
                  let window = prepareOverlayWindow(for: screen) else { continue }
            if window.frame != screen.frame {
                window.setFrame(screen.frame, display: false)
            }
            let view: SelectionOverlayView
            if let existing = window.contentView as? SelectionOverlayView, existing.screen.frame == screen.frame {
                view = existing
            } else {
                view = SelectionOverlayView(
                    frame: CGRect(origin: .zero, size: screen.frame.size),
                    controller: self,
                    screen: screen,
                    image: nil
                )
                window.contentView = view
            }
            view.update(image: image)
            view.needsDisplay = true
            view.displayIfNeeded()
            ready.append(window)
            readyDisplayIDs.insert(displayID)
        }

        // Displays that vanished between the capture start and now no longer get an overlay.
        let stale = overlayWindows.filter { !readyDisplayIDs.contains($0.key) }
        for (displayID, window) in stale {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            overlayWindows.removeValue(forKey: displayID)
        }

        windows = ready
        guard !windows.isEmpty else {
            teardown()
            completion?(nil)
            return
        }

        CATransaction.flush()
        Self.revealOverlayWindows(windows)
        CATransaction.flush()

        NSCursor.crosshair.set()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isActive else { return event }
            return self.handleKeyDown(event) ? nil : event
        }

        // Focus is taken only after the frozen frame reached the screen: activating swaps the menu
        // bar and resigns the previous app's key window, and doing that any earlier leaves those
        // changes visible for a frame or two over the live desktop — the flash when a capture opens.
        scheduleOverlayActivation()

        if let preselectRect {
            self.preselectRect = nil
            accept(SelectionResult(cocoaRect: preselectRect, windowID: nil, windowTitle: nil))
        }
    }

    // MARK: - Overlay windows

    /// Lays down one transparent, click-through overlay window per display before the capture.
    private func prepareOverlayWindows() {
        for screen in NSScreen.screens {
            _ = prepareOverlayWindow(for: screen)
        }
    }

    @discardableResult
    private func prepareOverlayWindow(for screen: NSScreen) -> SelectionOverlayWindow? {
        guard let displayID = screen.displayID else { return nil }
        if let existing = overlayWindows[displayID] { return existing }

        let window = SelectionOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        Self.configureOverlayWindowForPrewarm(window)
        window.contentView = SelectionOverlayView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            controller: self,
            screen: screen,
            image: nil
        )
        window.orderFrontRegardless()
        overlayWindows[displayID] = window
        windows.append(window)
        return window
    }

    /// The state a display overlay waits in while the capture is still running: fully transparent
    /// so it does not show anything, and click-through so it does not eat events.
    static func configureOverlayWindowForPrewarm(_ window: SelectionOverlayWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Well above the menu bar (24) and the Dock (20), without the extreme system shield level
        // that only login/lock UI uses.
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.isExcludedFromWindowsMenu = true
        window.acceptsMouseMovedEvents = true
        window.alphaValue = 0
        // The window server fades a window out when it is ordered out. On a full-screen frozen
        // overlay that crossfade from the dimmed frame to the live desktop reads as a brightness
        // flash when the capture is dismissed; a hard cut matches how the overlay appeared.
        window.animationBehavior = .none
    }

    /// Reveals the frozen frame and hands mouse input back to the overlay. Kept separate from the
    /// activation that follows so the ordering (draw → reveal → activate) stays explicit.
    static func revealOverlayWindows(_ windows: [SelectionOverlayWindow]) {
        for window in windows {
            window.orderFrontRegardless()
            window.ignoresMouseEvents = false
            window.alphaValue = 1
        }
    }

    /// Gives the overlay focus once it is on screen. The short delay covers the refresh needed for
    /// the revealed frame to be composited (the windows are already mapped, so this is one frame
    /// plus headroom) — without it the menu bar would visibly switch over the live desktop.
    private func scheduleOverlayActivation() {
        activationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isActive else { return }
            self.activateApp()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                self.focusOverlayWindow()
            }
        }
        activationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func focusOverlayWindow() {
        let key = windows.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? windows.first
        key?.makeKeyAndOrderFront(nil)
        if let view = key?.contentView {
            key?.makeFirstResponder(view)
        }
    }

    private func closeOverlayWindows() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        overlayWindows.removeAll()
    }

    /// Completes a teardown that was waiting for the previous app to come back to the front.
    private func finishPendingTeardownIfNeeded() {
        if let focusRestoreObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(focusRestoreObserver)
            self.focusRestoreObserver = nil
        }
        guard let pending = pendingTeardown else { return }
        pendingTeardown = nil
        pending()
    }

    func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func refresh() {
        for window in windows {
            window.contentView?.needsDisplay = true
        }
    }

    func updateCursor(_ point: CGPoint) {
        cursorPoint = point
    }

    // MARK: - Selection phase input

    func handleMouseDown(at point: CGPoint) {
        guard phase == .selecting else { return }
        cursorPoint = point
        if mode == .window {
            hoveredWindow = WindowHitTester.window(at: point, in: candidates)
            refresh()
            return
        }
        dragOrigin = point
        dragMoved = false
        selection = CGRect(origin: point, size: .zero)
        refresh()
    }

    func handleMouseDragged(to point: CGPoint) {
        guard phase == .selecting else { return }
        cursorPoint = point
        if mode == .window { return }
        guard let origin = dragOrigin else { return }
        if abs(point.x - origin.x) > 2 || abs(point.y - origin.y) > 2 {
            dragMoved = true
        }
        if dragMoved {
            // A region drag replaces the window highlight.
            hoveredWindow = nil
            selection = CGRect(point: origin, point: point)
        }
        refresh()
    }

    func handleMouseUp(at point: CGPoint) {
        guard phase == .selecting else { return }
        cursorPoint = point

        if mode == .window {
            if let window = WindowHitTester.window(at: point, in: candidates) {
                accept(SelectionResult(cocoaRect: window.cocoaFrame, windowID: window.id, windowTitle: window.title))
            } else {
                hoveredWindow = WindowHitTester.window(at: point, in: candidates)
                refresh()
            }
            return
        }

        defer { dragOrigin = nil }
        if !dragMoved {
            // A plain click captures the window under the cursor.
            let target = WindowHitTester.window(at: point, in: candidates) ?? hoveredWindow
            if let window = target {
                accept(SelectionResult(cocoaRect: window.cocoaFrame, windowID: window.id, windowTitle: window.title))
            } else {
                selection = .zero
                refresh()
            }
            return
        }
        let rect = selection.standardized.integral
        guard rect.width >= 4, rect.height >= 4 else {
            selection = .zero
            refresh()
            return
        }
        accept(SelectionResult(cocoaRect: rect, windowID: nil, windowTitle: nil))
    }

    func handleMouseMoved(to point: CGPoint) {
        guard phase == .selecting else {
            cursorPoint = point
            return
        }
        cursorPoint = point
        if dragOrigin == nil {
            hoveredWindow = WindowHitTester.window(at: point, in: candidates)
        }
        refresh()
    }

    // MARK: - Accepting a selection

    /// Handles a confirmed selection: runs the flow requested when the capture started.
    private func accept(_ result: SelectionResult) {
        selection = result.cocoaRect
        switch purpose {
        case .scroll:
            let handler = completion
            teardown(completion: { handler?(result) })
        case .extractText:
            enterEditing()
        case .edit:
            // The toolbar can be turned off in settings: capture straight to the clipboard then.
            if ScreenshotDefaults.showEditor {
                enterEditing()
            } else {
                copyWithoutEditing()
            }
        }
    }

    /// Fast path for users who disabled the annotation toolbar.
    private func copyWithoutEditing() {
        guard let image = ScreenCaptureService.compositeRegion(
            selection,
            images: images,
            scaleFor: { ScreenCaptureService.shared.backingScale(for: $0) }
        ) else {
            teardown()
            return
        }
        teardown()
        ScreenshotClipboard.copy(image: image)
        PasteboardHelper.showCopySuccessToast()
    }

    private func enterEditing() {
        guard let crop = ScreenCaptureService.compositeRegion(
            selection,
            images: images,
            scaleFor: { ScreenCaptureService.shared.backingScale(for: $0) }
        ) else {
            teardown()
            completion?(nil)
            return
        }
        let session = CaptureSession(image: crop)
        session.onNeedsDisplay = { [weak self] in
            self?.refresh()
        }
        sessionObserver = session.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
                self?.layoutToolbar()
            }
        }
        self.session = session
        phase = .editing
        selection = selection.standardized.integral
        for window in windows {
            if let view = window.contentView {
                window.invalidateCursorRects(for: view)
            }
        }
        NSCursor.arrow.set()
        refresh()
        layoutToolbar()
        if purpose == .extractText {
            session.recognizeText()
        }
    }

    // MARK: - Adjusting the capture frame

    /// Starts moving (when `handle` is nil) or resizing the capture frame while annotating. The
    /// frozen displays are still around, so the crop is simply rebuilt for the new frame.
    func beginSelectionAdjustment(handle: SelectionHandle?, at point: CGPoint) {
        guard phase == .editing, session != nil else { return }
        commitInlineTextEditors()
        frameDrag = FrameDrag(startSelection: selection.standardized, startPoint: point, handle: handle)
    }

    func updateSelectionAdjustment(to point: CGPoint) {
        guard phase == .editing, let drag = frameDrag else { return }
        let proposed: CGRect
        if let handle = drag.handle {
            proposed = SelectionAdjustment.resized(drag.startSelection, handle: handle, to: point)
        } else {
            proposed = SelectionAdjustment.moved(
                drag.startSelection,
                by: CGSize(width: point.x - drag.startPoint.x, height: point.y - drag.startPoint.y)
            )
        }
        let frame = SelectionAdjustment.clamped(proposed, to: ScreenGeometry.screensUnion).integral
        guard frame.width >= SelectionAdjustment.minimumSize,
              frame.height >= SelectionAdjustment.minimumSize else { return }
        applySelection(frame)
    }

    func endSelectionAdjustment() {
        frameDrag = nil
    }

    /// Rebuilds the crop for a new capture frame and keeps the annotations on the same spot of the
    /// frozen screen.
    private func applySelection(_ frame: CGRect) {
        guard let session else { return }
        let oldSelection = selection.standardized
        guard oldSelection != frame else { return }
        let oldImage = session.image
        guard let newImage = ScreenCaptureService.compositeRegion(
            frame,
            images: images,
            scaleFor: { ScreenCaptureService.shared.backingScale(for: $0) }
        ) else { return }

        let remap = SelectionAdjustment.imagePointTransform(
            from: oldSelection,
            oldImageSize: CGSize(width: oldImage.width, height: oldImage.height),
            to: frame,
            newImageSize: CGSize(width: newImage.width, height: newImage.height)
        )
        let visualScale = SelectionAdjustment.imagePixelScaleRatio(
            from: oldSelection,
            oldImageSize: CGSize(width: oldImage.width, height: oldImage.height),
            to: frame,
            newImageSize: CGSize(width: newImage.width, height: newImage.height)
        )
        selection = frame
        session.updateCapture(image: newImage, remapping: remap, visualScale: visualScale)
        refresh()
        layoutToolbar()
    }

    // MARK: - Editing actions

    func performCopy() {
        commitInlineTextEditors()
        guard let image = session?.flattenedImage() else { return }
        teardown()
        ScreenshotClipboard.copy(image: image)
        PasteboardHelper.showCopySuccessToast()
    }

    /// Copies recognized text and finishes the capture — the overlay closes instead of staying open
    /// with the text panel, the same way copying a screenshot behaves.
    func performCopyText(_ text: String) {
        guard !text.isEmpty else { return }
        teardown()
        ScreenshotClipboard.copy(text: text)
        PasteboardHelper.showCopySuccessToast()
    }

    func performSave() {
        commitInlineTextEditors()
        guard let image = session?.flattenedImage() else { return }
        teardown(restorePreviousApp: false)
        activateApp()
        ScreenshotSaver.save(image: image, suggestedName: nil, window: nil)
    }

    func performPin() {
        commitInlineTextEditors()
        guard let image = session?.flattenedImage() else { return }
        let origin = selection.center
        teardown(restorePreviousApp: false)
        PinWindowManager.shared.pin(image: image, at: origin)
    }

    func performExtractText() {
        commitInlineTextEditors()
        session?.recognizeText()
        layoutToolbar()
    }

    /// Commits an in-progress inline text annotation, if any.
    private func commitInlineTextEditors() {
        for window in windows {
            (window.contentView as? SelectionOverlayView)?.commitTextEditorIfNeeded()
        }
    }

    /// Enter / double click on the capture: copy (when the preference is on) and close.
    func finishEditing() {
        commitInlineTextEditors()
        if ScreenshotDefaults.autoCopy {
            performCopy()
        } else {
            teardown()
        }
    }

    func cancelEditing() {
        teardown()
    }

    func cancel() {
        if phase == .editing {
            cancelEditing()
        } else {
            finish(with: nil)
        }
    }

    private func finish(with result: SelectionResult?) {
        let handler = completion
        teardown(completion: { handler?(result) })
    }

    // MARK: - Toolbar

    private func overlayView(containing rect: CGRect) -> SelectionOverlayView? {
        var best: (view: SelectionOverlayView, area: CGFloat)?
        for window in windows {
            guard let view = window.contentView as? SelectionOverlayView else { continue }
            let local = rect.offsetBy(dx: -view.screen.frame.minX, dy: -view.screen.frame.minY)
            let intersection = local.intersection(view.bounds)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            if area > 0, best == nil || area > best!.area {
                best = (view, area)
            }
        }
        return best?.view
    }

    private func layoutToolbar() {
        guard phase == .editing,
              let session,
              let view = overlayView(containing: selection) else {
            removeToolbar()
            return
        }

        let host: NSHostingView<ScreenshotToolbarContainer>
        if let existing = toolbarHost as? NSHostingView<ScreenshotToolbarContainer> {
            host = existing
        } else {
            let created = NSHostingView(rootView: makeToolbar(session: session))
            created.wantsLayer = true
            toolbarHost = created
            host = created
        }
        if host.superview !== view {
            host.removeFromSuperview()
            view.addSubview(host)
        }

        let size = host.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        let selectionInView = view.selectionInView
        // Feishu placement: below the capture, above it when there is no room, and floating just
        // inside the bottom edge for captures that fill the whole screen.
        var origin = CGPoint(
            x: selectionInView.midX - size.width / 2,
            y: selectionInView.minY - size.height - 12
        )
        if origin.y < 8 {
            let above = selectionInView.maxY + 12
            if above + size.height <= view.bounds.height - 8 {
                origin.y = above
            } else {
                origin.y = selectionInView.minY + 12
            }
        }
        origin.y = min(origin.y, view.bounds.height - size.height - 8)
        origin.x = min(max(origin.x, 8), max(8, view.bounds.width - size.width - 8))
        origin.y = max(8, origin.y)
        host.frame = CGRect(origin: origin, size: size)
    }

    private func makeToolbar(session: CaptureSession) -> ScreenshotToolbarContainer {
        ScreenshotToolbarContainer(
            session: session,
            language: AppLanguage.current,
            onCopy: { [weak self] in self?.performCopy() },
            onSave: { [weak self] in self?.performSave() },
            onPin: { [weak self] in self?.performPin() },
            onExtractText: { [weak self] in self?.performExtractText() },
            onCopyText: { [weak self] text in self?.performCopyText(text) },
            onCancel: { [weak self] in self?.cancelEditing() }
        )
    }

    private func removeToolbar() {
        toolbarHost?.removeFromSuperview()
        toolbarHost = nil
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let editingText = (windows.first(where: { $0.isKeyWindow })?.firstResponder as? NSTextView)?.isFieldEditor ?? false

        if phase == .editing {
            if editingText {
                // Let the inline text editor handle typing, Enter and Esc itself.
                return false
            }
            if Int(event.keyCode) == kVK_Escape {
                // First Esc drops the selection, a second one leaves the capture.
                if session?.selectedShapeID != nil {
                    session?.select(nil)
                } else {
                    cancelEditing()
                }
                return true
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command), let characters = event.charactersIgnoringModifiers?.lowercased() {
                switch characters {
                case "c": performCopy(); return true
                case "s": performSave(); return true
                case "z": flags.contains(.shift) ? session?.redo() : session?.undo(); return true
                default: break
                }
            }
            switch Int(event.keyCode) {
            case kVK_Delete, kVK_ForwardDelete:
                session?.removeSelectedShape()
                return true
            case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
                guard session?.selectedShapeID != nil else { return false }
                let step: CGFloat = flags.contains(.shift) ? 10 : 1
                var dx: CGFloat = 0
                var dy: CGFloat = 0
                switch Int(event.keyCode) {
                case kVK_LeftArrow: dx = -step
                case kVK_RightArrow: dx = step
                case kVK_UpArrow: dy = -step
                default: dy = step
                }
                session?.nudgeSelectedShape(by: CGSize(width: dx, height: dy))
                return true
            default:
                break
            }
            if Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter {
                finishEditing()
                return true
            }
            if flags.isEmpty, let characters = event.charactersIgnoringModifiers?.lowercased() {
                if let tool = Self.toolShortcuts[characters] {
                    session?.tool = tool
                    return true
                }
            }
            return false
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            finish(with: nil)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            confirmHoveredOrSelection()
            return true
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            guard selection.width > 0 || selection.height > 0 else { return true }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            switch Int(event.keyCode) {
            case kVK_LeftArrow: dx = -step
            case kVK_RightArrow: dx = step
            case kVK_UpArrow: dy = step
            default: dy = -step
            }
            selection = selection.offsetBy(dx: dx, dy: dy)
            refresh()
            return true
        default:
            return false
        }
    }

    private static let toolShortcuts: [String: AnnotationTool] = [
        "v": .select,
        "r": .rectangle,
        "e": .ellipse,
        "a": .arrow,
        "p": .pen,
        "h": .highlighter,
        "t": .text,
        "m": .mosaic,
        "n": .number
    ]

    private func confirmHoveredOrSelection() {
        if dragMoved || selection.width >= 4 || selection.height >= 4 {
            let rect = selection.standardized.integral
            guard rect.width >= 4, rect.height >= 4 else { return }
            accept(SelectionResult(cocoaRect: rect, windowID: nil, windowTitle: nil))
            return
        }
        if let hovered = hoveredWindow {
            accept(SelectionResult(cocoaRect: hovered.cocoaFrame, windowID: hovered.id, windowTitle: hovered.title))
        }
    }

    // MARK: - Teardown

    private func teardown(restorePreviousApp: Bool = true, completion handler: (() -> Void)? = nil) {
        if pendingTeardown != nil {
            finishPendingTeardownIfNeeded()
        }
        isActive = false
        phase = .selecting
        activationWorkItem?.cancel()
        activationWorkItem = nil
        frameDrag = nil
        sessionObserver?.cancel()
        sessionObserver = nil
        removeToolbar()
        // A late text-recognition pass must not redraw through a session that is going away.
        session?.onNeedsDisplay = nil
        session = nil
        images.removeAll()
        candidates.removeAll()
        completion = nil
        preselectRect = nil
        hoveredWindow = nil
        dragOrigin = nil
        selection = .zero
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        NSCursor.arrow.set()

        let closeOverlay = { [weak self] in
            guard let self else {
                handler?()
                return
            }
            self.closeOverlayWindows()
            self.pendingTeardown = nil
            handler?()
        }

        // Focus is handed back while the frozen frame still covers the screen, and the windows only
        // close once the other app is frontmost. Closing them first shows the live desktop with
        // CopyGlass still active before the menu bar switches back — the flash when a capture closes.
        guard restorePreviousApp,
              let app = previousApp,
              !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier
        else {
            previousApp = nil
            closeOverlay()
            return
        }
        previousApp = nil
        pendingTeardown = closeOverlay
        focusRestoreObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if activated?.processIdentifier == app.processIdentifier {
                self?.finishPendingTeardownIfNeeded()
            }
        }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [])
        }
        // Never let a hung app keep the frozen frame on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.finishPendingTeardownIfNeeded()
        }
    }
}

// MARK: - Window

final class SelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    /// Deliberately not a "main" window: the overlay must stay out of window/Space management so the
    /// desktop does not animate when a capture opens or closes.
    override var canBecomeMain: Bool { false }
    override func rightMouseDown(with event: NSEvent) {
        RegionSelectionController.shared.cancel()
    }
}
