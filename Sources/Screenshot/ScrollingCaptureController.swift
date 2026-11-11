import Foundation
import AppKit
import SwiftUI
import CoreGraphics
import Carbon
import ScreenCaptureKit

/// Manual scrolling capture.
///
/// The user picks a region once, then scrolls the page by hand while frames of that region are
/// captured and stitched into one long image (the Feishu arrangement: the app never scrolls for the
/// user). The stitched result opens in the editor window, where it can be annotated but no longer
/// re-captured or resized.
///
/// The controller is main-queue confined; it is declared `@unchecked Sendable` because the
/// asynchronous capture tasks hop back to the main queue before touching any of its state.
final class ScrollingCaptureController: @unchecked Sendable {
    static let shared = ScrollingCaptureController()

    private(set) var isRunning = false

    private var region: CGRect = .zero
    private var completion: ((CGImage?) -> Void)?
    private var session: ScrollStitchSession?
    private var hud: ScrollingHUDController?
    private var preview: ScrollingPreviewController?
    private var borderWindows: [ScrollingBorderWindow] = []
    private var excludedWindows: [SCWindow] = []
    private var captureTimer: Timer?
    private var keyMonitor: Any?
    /// System scroll events accumulated since the last capture, in points; used to predict the
    /// pixel shift and stop repetitive content from aligning to the wrong period.
    private var scrollAccumulator: CGFloat = 0
    private var scrollMonitor: Any?
    /// Row delta per point of scrolling, flipped automatically if the system's sign convention
    /// turns out to be the opposite of what was assumed.
    private var scrollSign: CGFloat = -1
    /// Prediction attached to the frame currently being captured.
    private var pendingExpectedShift: (rows: Int, tolerance: Int)?
    private var scrollSignCalibrations = 0
    /// Keeps App Nap from throttling the capture timers while the user scrolls another app.
    private var activity: NSObjectProtocol?
    private var inFlight = false
    private var idleStreak = 0
    private var didReceiveFirstFrame = false
    private var didReachLimit = false
    private var finishInProgress = false
    private var consecutiveFailures = 0
    private var startedAt = Date()
    private var currentStatus: String?

    private let stitchQueue = DispatchQueue(label: "copyglass.scrolling-capture.stitch", qos: .userInitiated)
    /// Fast cadence while the page is moving; slower when nothing changes to keep the session cheap.
    private let activeInterval: TimeInterval = 0.10
    private let idleInterval: TimeInterval = 0.22
    private let idleFramesBeforeSlowdown = 6
    private let firstFrameDelay: TimeInterval = 0.15
    private let maxSessionDuration: TimeInterval = 300
    private let minimumRegionSide: CGFloat = 40

    private init() {}

    func start(region: CGRect, completion: @escaping (CGImage?) -> Void) {
        guard !isRunning else { return }
        let target = region.standardized.integral
        guard target.width >= minimumRegionSide, target.height >= minimumRegionSide else {
            NSSound.beep()
            return
        }

        isRunning = true
        finishInProgress = false
        self.region = target
        self.completion = completion
        session = nil
        hud = nil
        borderWindows = []
        excludedWindows = []
        captureTimer?.invalidate()
        captureTimer = nil
        inFlight = false
        idleStreak = 0
        didReceiveFirstFrame = false
        didReachLimit = false
        consecutiveFailures = 0
        startedAt = Date()
        currentStatus = nil
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "Manual scrolling capture"
        )

        borderWindows = ScrollingBorderWindow.makeWindows(around: target)
        let hud = ScrollingHUDController(
            onFinish: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }
        )
        hud.show(near: target)
        self.hud = hud

        scrollAccumulator = 0
        pendingExpectedShift = nil
        scrollSignCalibrations = 0
        installScrollMonitor()

        let preview = ScrollingPreviewController()
        preview.show(near: target)
        self.preview = preview

        installKeyMonitor()

        var windowNumbers = borderWindows.map { $0.windowNumber }
        if let hudNumber = hud.panelWindowNumber {
            windowNumbers.append(hudNumber)
        }
        if let previewNumber = preview.panelWindowNumber {
            windowNumbers.append(previewNumber)
        }

        // The frame indicator and the HUD have to be on screen before their windows can be resolved
        // for the capture exclusion; the first frame waits just long enough for both.
        DispatchQueue.main.asyncAfter(deadline: .now() + firstFrameDelay) { [weak self] in
            guard let self, self.isRunning else { return }
            ScreenCaptureService.shared.invalidateContentCache()
            Task {
                let excluded = await ScreenCaptureService.shared.shareableWindows(forWindowNumbers: windowNumbers)
                DispatchQueue.main.async {
                    guard self.isRunning else { return }
                    self.excludedWindows = excluded
                    self.scheduleNextCapture()
                }
            }
        }
    }

    func cancel() {
        finish(notify: false)
    }

    private func finish(notify: Bool = true) {
        guard isRunning, !finishInProgress else { return }
        finishInProgress = true
        isRunning = false
        captureTimer?.invalidate()
        captureTimer = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        hud?.close()
        hud = nil
        preview?.close()
        preview = nil
        for window in borderWindows {
            window.orderOut(nil)
            window.close()
        }
        borderWindows.removeAll()
        excludedWindows.removeAll()

        let session = self.session
        self.session = nil
        let handler = completion
        completion = nil
        // The final image can be tall; compose it off the main thread.
        stitchQueue.async {
            let image = session?.finalImage()
            DispatchQueue.main.async {
                handler?(notify ? image : nil)
            }
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        // Best effort, matching the previous implementation: global key monitors need the
        // accessibility trust the app already asks for elsewhere. The HUD buttons always work.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRunning else { return }
            switch Int(event.keyCode) {
            case kVK_Escape:
                DispatchQueue.main.async { self.cancel() }
            case kVK_Return, kVK_ANSI_KeypadEnter:
                DispatchQueue.main.async { self.finish() }
            default:
                break
            }
        }
    }

    // MARK: - Scroll prediction

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return }
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                self.scrollAccumulator += delta
            }
        }
    }

    /// Pixel shift predicted from the scroll events that happened since the previous capture.
    private func predictedShift(backingScale: CGFloat) -> (rows: Int, tolerance: Int)? {
        let accumulated = scrollAccumulator
        scrollAccumulator = 0
        guard abs(accumulated) > 0.5 else { return nil }
        let rows = Int((accumulated * scrollSign * backingScale).rounded())
        guard abs(rows) >= 2 else { return nil }
        return (rows, max(60, abs(rows) / 2))
    }

    // MARK: - Capture loop

    private func scheduleNextCapture(after delay: TimeInterval? = nil) {
        captureTimer?.invalidate()
        guard isRunning, !didReachLimit else { return }
        let interval = delay ?? (idleStreak >= idleFramesBeforeSlowdown ? idleInterval : activeInterval)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.captureFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        captureTimer = timer
    }

    private func captureFrame() {
        guard isRunning, !inFlight else { return }
        if Date().timeIntervalSince(startedAt) > maxSessionDuration {
            finish()
            return
        }
        inFlight = true
        let region = self.region
        let excluded = excludedWindows
        let backingScale = ScreenGeometry.screen(bestMatching: region)?.backingScaleFactor ?? 2
        pendingExpectedShift = predictedShift(backingScale: backingScale)
        Task {
            do {
                let frame = try await ScreenCaptureService.shared.captureRegion(region, excluding: excluded)
                DispatchQueue.main.async { self.handle(frame: frame) }
            } catch {
                DispatchQueue.main.async { self.handleCaptureFailure(error) }
            }
        }
    }

    private func handleCaptureFailure(_ error: Error) {
        inFlight = false
        consecutiveFailures += 1
        guard isRunning else { return }
        if !didReceiveFirstFrame {
            finish(notify: false)
            ScreenshotController.shared.presentError(error)
            return
        }
        if consecutiveFailures >= 3 {
            finish()
            return
        }
        scheduleNextCapture(after: activeInterval)
    }

    private func handle(frame: CGImage) {
        inFlight = false
        consecutiveFailures = 0
        guard isRunning else { return }

        if session == nil {
            guard let created = ScrollStitchSession(firstFrame: frame) else {
                finish()
                return
            }
            pendingExpectedShift = nil
            session = created
            didReceiveFirstFrame = true
            preview?.update(
                snapshot: created.previewSnapshot,
                frames: created.capturedFrames,
                height: created.stitchedHeight,
                status: nil
            )
            scheduleNextCapture()
            return
        }

        guard let session else { return }
        let prediction = pendingExpectedShift
        pendingExpectedShift = nil
        stitchQueue.async { [weak self] in
            let outcome = session.ingest(
                frame,
                expectedRows: prediction?.rows,
                expectedTolerance: prediction?.tolerance
            )
            let frames = session.capturedFrames
            let height = session.stitchedHeight
            let limit = session.reachedLimit
            let shift = session.lastShift
            let snapshot = session.previewSnapshot
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                self.apply(
                    outcome: outcome,
                    frames: frames,
                    height: height,
                    limit: limit,
                    shift: shift,
                    prediction: prediction,
                    snapshot: snapshot
                )
            }
        }
    }

    private func apply(
        outcome: ScrollStitchSession.Outcome,
        frames: Int,
        height: Int,
        limit: Bool,
        shift: Int,
        prediction: (rows: Int, tolerance: Int)?,
        snapshot: ScrollStitchSession.PreviewSnapshot
    ) {
        // Recalibrate the assumed scroll direction once the image proves the opposite sign.
        if case .extended = outcome,
           let prediction,
           abs(prediction.rows) >= 16,
           abs(shift) >= 16,
           (shift > 0) != (prediction.rows > 0),
           scrollSignCalibrations < 1 {
            scrollSign *= -1
            scrollSignCalibrations += 1
        }

        switch outcome {
        case .extended:
            idleStreak = 0
            currentStatus = nil
        case .unchanged:
            idleStreak += 1
        case .noMatch:
            // The frame did not overlap the last accepted one: drop it and ask the user to scroll
            // back a little instead of corrupting the stitched image.
            idleStreak += 1
            currentStatus = L10n.t(.scrollingCaptureSlowDown, lang: AppLanguage.current)
        case .limitReached, .failed:
            break
        }

        if limit {
            didReachLimit = true
            currentStatus = L10n.t(.scrollingCaptureMaxLength, lang: AppLanguage.current)
        }
        preview?.update(snapshot: snapshot, frames: frames, height: height, status: currentStatus)

        guard !didReachLimit else { return }
        scheduleNextCapture()
    }
}

// MARK: - HUD

/// Compact finish/cancel bar while a manual scrolling capture runs.
///
/// The progress text lives in the live preview panel, so the bar itself only carries the two
/// actions and uses the same floating dark toolbar look as the normal screenshot editor.
final class ScrollingHUDController {
    private var panel: NSPanel?
    private let onFinish: () -> Void
    private let onCancel: () -> Void

    init(onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    var panelWindowNumber: Int? {
        guard let panel, panel.isVisible else { return nil }
        return panel.windowNumber
    }

    func show(near region: CGRect) {
        let host = NSHostingView(rootView: ScrollingHUDView(
            onFinish: onFinish,
            onCancel: onCancel,
            language: AppLanguage.current
        ))
        let size = host.fittingSize
        guard size.width > 1, size.height > 1 else { return }

        let screen = ScreenGeometry.screen(bestMatching: region) ?? NSScreen.main
        var origin = CGPoint(x: region.midX - size.width / 2, y: region.minY - size.height - 14)
        if let frame = screen?.frame {
            origin.x = min(max(origin.x, frame.minX + 12), frame.maxX - size.width - 12)
            if origin.y < frame.minY + 12 {
                let above = region.maxY + 14
                if above + size.height <= frame.maxY - 12 {
                    origin.y = above
                } else {
                    // No room around the capture: float over it. The panel is excluded from the
                    // captures, so it cannot leak into the stitched image.
                    origin.y = max(frame.minY + 12, region.minY + 12)
                }
            }
        }

        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        host.frame = CGRect(origin: .zero, size: size)
        panel.contentView = host
        panel.orderFrontRegardless()

        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

/// The compact bar content: cancel and finish, styled like the normal capture toolbar.
struct ScrollingHUDView: View {
    let onFinish: () -> Void
    let onCancel: () -> Void
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 3) {
            iconButton("xmark", help: L10n.t(.cancel, lang: language)) { onCancel() }
            iconButton("checkmark", isProminent: true, help: L10n.t(.scrollingCaptureDone, lang: language)) { onFinish() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        )
        .environment(\.colorScheme, .dark)
        .environment(\.appLanguage, language)
    }

    private func iconButton(
        _ systemName: String,
        isProminent: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isProminent ? Color.accentColor.opacity(0.5) : Color.clear)
                )
                .foregroundStyle(Color.white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Frame indicator

/// Click-through frame indicator for the region being captured.
///
/// The ring is painted just outside the capture rectangle (and the window is also excluded from the
/// captures) so it can never end up in the stitched image.
final class ScrollingBorderWindow: NSWindow {
    static func makeWindows(around region: CGRect) -> [ScrollingBorderWindow] {
        NSScreen.screens.compactMap { screen in
            guard screen.frame.intersects(region) else { return nil }
            return ScrollingBorderWindow(screen: screen, region: region)
        }
    }

    private init(screen: NSScreen, region: CGRect) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Below the HUD (statusBar) but above ordinary windows, full-screen apps included.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isMovable = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        let local = region.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        contentView = ScrollingBorderView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            region: local
        )
        orderFrontRegardless()
    }
}

private final class ScrollingBorderView: NSView {
    private let region: CGRect

    init(frame: NSRect, region: CGRect) {
        self.region = region
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = region.standardized
        guard rect.width > 1, rect.height > 1 else { return }
        // Painted outside the captured rectangle: a dark halo first so the ring stays visible on
        // light and dark content, then the accent-coloured frame.
        let halo = NSBezierPath(rect: rect.insetBy(dx: -3, dy: -3))
        halo.lineWidth = 4
        NSColor.black.withAlphaComponent(0.4).setStroke()
        halo.stroke()

        let ring = NSBezierPath(rect: rect.insetBy(dx: -3, dy: -3))
        ring.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        ring.stroke()
    }
}
