import Foundation
import AppKit
import CoreGraphics

/// Captures a tall region by scrolling the target content and stitching the frames together.
///
/// The user picks a region once; from then on the controller warps the cursor into that region,
/// posts pixel-based scroll events and captures the region repeatedly. Frames are aligned with
/// ImageStitcher and composed into a single long image.
final class ScrollingCaptureController {
    static let shared = ScrollingCaptureController()

    private(set) var isRunning = false

    private var region: CGRect = .zero
    private var accumulator: CGImage?
    private var lastSignature: ImageRowSignature?
    private var frameCount = 0
    private var noProgressCount = 0
    private var cancelled = false
    private var completion: ((CGImage?) -> Void)?
    private var hud: ScrollingHUDController?
    private var globalMonitor: Any?
    private var scrollDirection: Int32 = -1
    private var reversedOnce = false
    private let maxHeight = 16000
    private let frameDelay: TimeInterval = 0.38

    private init() {}

    func start(region: CGRect, completion: @escaping (CGImage?) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        cancelled = false
        self.region = region.standardized.integral
        self.completion = completion
        accumulator = nil
        lastSignature = nil
        frameCount = 0
        noProgressCount = 0
        reversedOnce = false

        installEscapeMonitor()
        hud = ScrollingHUDController(
            onStop: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }
        )
        hud?.show(near: self.region)
        warpCursor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.captureNextFrame()
        }
    }

    func cancel() {
        cancelled = true
        finish(notify: false)
    }

    private func finish(notify: Bool = true) {
        guard isRunning else { return }
        isRunning = false
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        hud?.close()
        hud = nil
        let result = cancelled ? nil : accumulator
        let handler = completion
        completion = nil
        if notify {
            handler?(result)
        } else {
            handler?(nil)
        }
    }

    private func installEscapeMonitor() {
        // Best effort: global key monitors only deliver events when the app is trusted for
        // accessibility, which the app already asks for elsewhere. The HUD buttons always work.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRunning else { return }
            if Int(event.keyCode) == 53 {
                DispatchQueue.main.async { self.finish() }
            }
        }
    }

    private func warpCursor() {
        let point = ScreenGeometry.quartzPoint(fromCocoa: region.center)
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func captureNextFrame() {
        guard isRunning, !cancelled else { return }
        warpCursor()
        Task {
            do {
                let frame = try await ScreenCaptureService.shared.captureRegion(self.region)
                await MainActor.run { self.process(frame: frame) }
            } catch {
                await MainActor.run { self.finish() }
            }
        }
    }

    private func process(frame: CGImage) {
        guard isRunning else { return }
        guard let signature = ImageStitcher.signature(of: frame) else {
            finish()
            return
        }

        var progressed = false
        if let accumulator, let previousSignature = lastSignature {
            if ImageStitcher.areNearlyIdentical(previousSignature, signature) {
                progressed = false
            } else if let match = ImageStitcher.findMatch(previous: previousSignature, next: signature),
                      match.appendedRows(nextHeight: frame.height) > 4,
                      let composed = ImageStitcher.compose(previous: accumulator, next: frame, match: match) {
                self.accumulator = composed
                progressed = true
            }
        } else {
            accumulator = frame
            progressed = true
        }

        lastSignature = signature
        if progressed {
            frameCount += 1
            noProgressCount = 0
        } else {
            noProgressCount += 1
            if noProgressCount >= 2 {
                // Nothing moved: either the page ended or the scroll direction is inverted
                // (for example when the system's natural scrolling setting is in play).
                if !reversedOnce {
                    reversedOnce = true
                    scrollDirection = -scrollDirection
                    noProgressCount = 0
                } else {
                    finish()
                    return
                }
            }
        }

        hud?.update(frameCount: frameCount, height: accumulator?.height ?? frame.height)

        if (accumulator?.height ?? 0) >= maxHeight {
            finish()
            return
        }

        postScroll()
        DispatchQueue.main.asyncAfter(deadline: .now() + frameDelay) { [weak self] in
            self?.captureNextFrame()
        }
    }

    private func postScroll() {
        let amount = max(60, Int(region.height * 0.45))
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: scrollDirection * Int32(amount),
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.location = ScreenGeometry.quartzPoint(fromCocoa: region.center)
        event.post(tap: .cghidEventTap)
    }
}

// MARK: - HUD

final class ScrollingHUDController {
    private var panel: NSPanel?
    private let onStop: () -> Void
    private let onCancel: () -> Void
    private var detailLabel: NSTextField?

    init(onStop: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onStop = onStop
        self.onCancel = onCancel
    }

    func show(near region: CGRect) {
        let width: CGFloat = 320
        let height: CGFloat = 116
        let screen = ScreenGeometry.screen(bestMatching: region) ?? NSScreen.main
        var origin = CGPoint(x: region.midX - width / 2, y: region.minY - height - 16)
        if let frame = screen?.frame {
            origin.x = min(max(origin.x, frame.minX + 12), frame.maxX - width - 12)
            if origin.y < frame.minY + 12 {
                origin.y = min(region.maxY + 16, frame.maxY - height - 12)
            }
        }

        let panel = NSPanel(
            contentRect: CGRect(x: origin.x, y: origin.y, width: width, height: height),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let content = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active

        let title = NSTextField(labelWithString: L10n.t(.scrollingCaptureTitle, lang: AppLanguage.current))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.frame = CGRect(x: 16, y: height - 42, width: width - 32, height: 20)

        let detail = NSTextField(labelWithString: L10n.t(.scrollingCaptureHint, lang: AppLanguage.current))
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.frame = CGRect(x: 16, y: height - 64, width: width - 32, height: 18)

        let cancelButton = NSButton(title: L10n.t(.cancel, lang: AppLanguage.current), target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = CGRect(x: 16, y: 14, width: 96, height: 28)

        let stopButton = NSButton(title: L10n.t(.scrollingCaptureStop, lang: AppLanguage.current), target: self, action: #selector(stopTapped))
        stopButton.bezelStyle = .rounded
        stopButton.frame = CGRect(x: width - 112, y: 14, width: 96, height: 28)

        content.addSubview(title)
        content.addSubview(detail)
        content.addSubview(cancelButton)
        content.addSubview(stopButton)
        panel.contentView = content
        panel.orderFrontRegardless()

        self.panel = panel
        self.detailLabel = detail
    }

    func update(frameCount: Int, height: Int) {
        let template = L10n.t(.scrollingCaptureProgress, lang: AppLanguage.current)
        detailLabel?.stringValue = template
            .replacingOccurrences(of: "{count}", with: String(frameCount))
            .replacingOccurrences(of: "{height}", with: String(height))
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    @objc private func stopTapped() { onStop() }
    @objc private func cancelTapped() { onCancel() }
}
