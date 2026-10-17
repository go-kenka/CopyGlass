import SwiftUI
import AppKit

@main
struct CopyGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // CopyGlass lives in the menu bar (LSUIElement). This scene backs the standard "Settings…"
        // item (Cmd+,) and shows the same settings UI as the main window — it used to hold an
        // EmptyView, which made Cmd+, open a blank window.
        Settings {
            AppContainerView(content: SettingsView(clipboardManager: ClipboardManager.shared))
                .frame(minWidth: 820, minHeight: 560)
                .background(SettingsWindowProbe().frame(width: 1, height: 1))
        }
    }
}

/// Dismisses the settings window when SwiftUI presents it on its own during launch.
///
/// The Settings scene is the app's only scene, so SwiftUI opens its window at launch even though
/// CopyGlass is a menu bar agent — that would pop a window at every login. The clean fix,
/// Scene.defaultLaunchBehavior(.suppressed), requires macOS 15 while the app supports macOS 14.
/// Opening Settings from the menu (Cmd+,) is only possible while the app is active, so presenting
/// the window while the app is inactive means nobody asked for it.
private struct SettingsWindowProbe: NSViewRepresentable {
    final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !NSApp.isActive else { return }
            DispatchQueue.main.async {
                window.orderOut(nil)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { ProbeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the status bar controller
        statusBarController = StatusBarController()

        // Load the Vision text-recognition models in the background: the first request of a session
        // otherwise blocks for ~10s while macOS reads the assets from disk.
        OCRService.warmUpIfNeeded()

        // Prepare ScreenCaptureKit's shareable content so the frame is captured the instant the
        // capture hotkey is pressed (a slow first enumeration makes the frozen screen look stale).
        ScreenCaptureService.shared.warmUp()

        // 在应用启动时检查辅助功能权限
        checkAccessibilityPermission()
    }

    private func checkAccessibilityPermission() {
        // 检查是否有辅助功能权限
        if !PasteboardHelper.accessibilityTrusted(prompt: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // 显示需要辅助功能权限的提示
                let alert = NSAlert()
                alert.messageText = "需要辅助功能权限"
                alert.informativeText = "CopyGlass需要辅助功能权限才能实现自动粘贴功能。请在系统偏好设置中授予权限。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "打开设置")
                alert.addButton(withTitle: "稍后")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    PasteboardHelper.openAccessibilitySettings()
                }
            }
        }
    }
}
