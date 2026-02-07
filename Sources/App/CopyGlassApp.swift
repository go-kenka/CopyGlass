import SwiftUI

@main
struct CopyGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty scene for LSUIElement app to avoid creating a default window
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the status bar controller
        statusBarController = StatusBarController()

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
