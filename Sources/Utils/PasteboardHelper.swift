import AppKit
import ApplicationServices
import UserNotifications

class PasteboardHelper: NSObject, UNUserNotificationCenterDelegate {
    // 记住之前激活的应用
    private static var lastActiveApp: NSRunningApplication?

    // 在CopyGlass窗口出现前捕获当前激活的应用
    static func captureActiveApp() {
        lastActiveApp = NSWorkspace.shared.frontmostApplication
    }

    // 恢复之前的应用
    static func restorePreviousApp() {
        guard let app = lastActiveApp else { return }
        app.activate(options: [])
    }

    // 恢复应用并自动粘贴（用于弹窗选择后）
    static func restoreAndPaste() {
        restorePreviousApp()
        // 延迟执行粘贴，确保应用已激活
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            pasteToFrontmostApp()
        }
    }

    // 使用 CGEvent 模拟 Cmd+V 粘贴
    static func pasteToFrontmostApp() {
        guard accessibilityTrusted(prompt: false) else { return }

        let source = CGEventSource(stateID: .combinedSessionState)

        // V 键的虚拟键码是 0x09
        let vKeyCode: CGKeyCode = 0x09

        // 创建 Cmd+V 按下事件
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand

        // 创建 Cmd+V 释放事件
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        // 发送事件到系统
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // 简单的粘贴方法，用于兼容性
    static func paste() {
        // 仅用于保持兼容，不执行任何操作
    }

    private static var notificationDelegate = NotificationDelegate()

    static func showCopySuccessToast() {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate

        let content = UNMutableNotificationContent()
        content.title = "已复制到剪贴板"
        content.body = "按 Cmd+V 粘贴"
        content.sound = nil // 无声音

        // 立即显示通知
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // 立即触发
        )

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                center.add(request)

                // 2秒后自动移除通知
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
                }
            }
        }
    }

    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Notification Delegate

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
