import SwiftUI
import AppKit

/// Identifies the app's main window among `NSApplication.windows`.
enum MainWindow {
    static let sceneID = "main-window"
}

/// Lets AppKit call sites (status bar menu, global hotkey) open the SwiftUI-owned main window even
/// after its window has been closed.
final class MainWindowPresenter {
    static let shared = MainWindowPresenter()
    var show: (() -> Void)?
}

@main
struct CopyGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The main window is a regular SwiftUI window scene. CopyGlass lives in the menu bar
        // (LSUIElement) and opens this window from the status item, the global shortcut or Cmd+,.
        //
        // It must stay a scene window: a hand-built NSWindow + NSHostingView puts
        // NavigationSplitView into its in-content fallback layout, where the sidebar search field
        // loses its margin to the list and the sidebar toggle is drawn next to the traffic lights
        // instead of at the trailing edge of the sidebar.
        Window("CopyGlass", id: MainWindow.sceneID) {
            AppContainerView(content: SettingsView(clipboardManager: ClipboardManager.shared))
                .frame(minWidth: 700, minHeight: 550)
                .background(LaunchWindowSuppressor().frame(width: 1, height: 1))
                .background(MainWindowPresenterBridge().frame(width: 1, height: 1))
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.t(.preferences, lang: L10n.currentLanguage) + "…") {
                    MainWindowPresenter.shared.show?()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Captures SwiftUI's `openWindow` action so the AppKit side can show the main window again after
/// the user closed it.
private struct MainWindowPresenterBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                MainWindowPresenter.shared.show = { openWindow(id: MainWindow.sceneID) }
            }
    }
}

/// SwiftUI presents the main window once at launch because it is the app's only scene. CopyGlass is
/// a menu bar agent, so dismiss that launch presentation; asking for the window later (status item,
/// global shortcut, Cmd+,) shows it again. `Scene.defaultLaunchBehavior(.suppressed)` would be the
/// clean fix, but it requires macOS 15 while CopyGlass supports macOS 14.
private struct LaunchWindowSuppressor: NSViewRepresentable {
    final class SuppressorView: NSView {
        private static var didHideLaunchWindow = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !Self.didHideLaunchWindow else { return }
            Self.didHideLaunchWindow = true
            DispatchQueue.main.async {
                window.orderOut(nil)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { SuppressorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // CopyGlass is a menu bar agent: its main window is hidden at launch and the app has to
        // keep running without any visible window. Otherwise AppKit's automatic termination quits
        // the app right after that window is dismissed.
        ProcessInfo.processInfo.disableAutomaticTermination("CopyGlass runs in the menu bar")

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

    /// A menu bar app keeps running after its main window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
