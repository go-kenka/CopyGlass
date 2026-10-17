import SwiftUI

enum L10nKey: String, CaseIterable {
    case general
    case history
    case quickReply
    case about
    case search
    case shortcut
    case permissions
    case preferences
    case appearanceLanguage
    case language
    case theme
    case system
    case light
    case dark
    case resetToDefaults
    case change
    case openAccessibilitySettings
    case enabled
    case disabled
    case enterToCopy
    case historyList
    case quickReplyList
    case showMainWindow
    case quit
    
    case generalSubtitle
    case preferencesSubtitle
    case hotkeySubtitle
    case permissionsRowSubtitle
    case appearanceLanguageSubtitle
    
    case globalHotkeys
    case hotkeyMustIncludeCmd
    case hotkeyAlreadyUsed
    case setHotkey
    case pressHotkeyHint
    case recording
    
    case retention
    case startup
    case keepItemsFor
    case days7
    case days30
    case forever
    case startAtLogin
    
    case accessibility
    case status
    case requiredForAutoPaste
    case actions
    case refreshStatus
    case requestPermission
    case debug
    case appPath
    case bundleId
    case rebundleHint
    
    case historySubtitle
    case clipboardItems
    case clipboardItemsSubtitle
    case clearHistory
    case clipboardHistory
    case clipboardHistorySubtitle
    
    case quickReplySubtitle
    case quickReplies
    case quickRepliesSubtitle
    
    case new
    case delete
    case cancel
    case save
    
    case newQuickReply
    case title
    case shortcutOptional
    
    case aboutSubtitle
    case version
    case platform
    case highlights
    case highlightHistoryRichText
    case highlightQuickReplies
    case highlightMenuBarHotkey

    // MARK: Screenshot
    case screenshot
    case screenshotSubtitle
    case screenshotEditor
    case screenshotPreferences
    case screenshotPreferencesSubtitle
    case screenshotAutoCopy
    case screenshotShowEditor
    case screenshotSaveDirectory
    case screenshotChooseFolder
    case screenshotAskEveryTime
    case screenshotFormat
    case screenshotQuality
    case screenshotCaptureGroup
    case screenshotPinGroup

    case captureRegion
    case captureWindow
    case captureFullScreen
    case captureScrolling
    case extractText
    case captureAndPin

    case selectionHintRegion
    case selectionHintWindow
    case selectionHintEditing
    case strokeWidth
    case back
    case copiedText
    case ocrFailed
    case noTextFound

    case scrollingCaptureTitle
    case scrollingCaptureHint
    case scrollingCaptureStop
    case scrollingCaptureProgress

    case ocrTitle
    case ocrRecognizing
    case ocrEmpty
    case ocrShowBoxes
    case copyAll
    case copy
    case copied
    case copiedToClipboard
    case close
    case undo
    case redo
    case clear
    case pinned

    case toolSelect
    case toolRectangle
    case toolEllipse
    case toolArrow
    case toolPen
    case toolHighlighter
    case toolText
    case toolMosaic
    case toolNumber
    case annotationTextPlaceholder

    case pin
    case pinOpacity
    case pinResizeToOriginal
    case pinUnpinAll

    case screenRecording
    case screenRecordingPermissionTitle
    case screenRecordingPermissionMessage
    case openSystemSettings
    case screenshotPermissionRequired
    case screenshotFailed
}

enum L10n {
    static func t(_ key: L10nKey, lang: AppLanguage) -> String {
        (lang == .zhHans ? zh : en)[key] ?? key.rawValue
    }
    
    private static let en: [L10nKey: String] = [
        .general: "General",
        .history: "History",
        .quickReply: "Quick Reply",
        .about: "About",
        .search: "Search",
        .shortcut: "Shortcut",
        .permissions: "Permissions",
        .preferences: "Preferences",
        .appearanceLanguage: "Appearance & Language",
        .language: "Language",
        .theme: "Theme",
        .system: "System",
        .light: "Light",
        .dark: "Dark",
        .resetToDefaults: "Reset to Defaults",
        .change: "Change",
        .openAccessibilitySettings: "Open Accessibility Settings",
        .enabled: "Enabled",
        .disabled: "Disabled",
        .enterToCopy: "Enter to copy",
        .historyList: "History List",
        .quickReplyList: "Quick Reply List",
        .showMainWindow: "Show Main Window",
        .quit: "Quit",
        
        .generalSubtitle: "Preferences for CopyGlass.",
        .preferencesSubtitle: "Retention and startup",
        .hotkeySubtitle: "Show history with a hotkey",
        .permissionsRowSubtitle: "Accessibility for auto paste",
        .appearanceLanguageSubtitle: "Theme and language",
        
        .globalHotkeys: "Global Hotkeys",
        .hotkeyMustIncludeCmd: "Hotkey must include ⌘ to avoid interfering with typing.",
        .hotkeyAlreadyUsed: "This hotkey is already used by another action.",
        .setHotkey: "Set Hotkey",
        .pressHotkeyHint: "Press a key combination (must include ⌘). Esc to cancel.",
        .recording: "Recording…",
        
        .retention: "Retention",
        .startup: "Startup",
        .keepItemsFor: "Keep items for",
        .days7: "7 Days",
        .days30: "30 Days",
        .forever: "Forever",
        .startAtLogin: "Start at Login",
        
        .accessibility: "Accessibility",
        .status: "Status",
        .requiredForAutoPaste: "Required for auto paste.",
        .actions: "Actions",
        .refreshStatus: "Refresh Status",
        .requestPermission: "Request Permission",
        .debug: "Debug",
        .appPath: "App Path",
        .bundleId: "Bundle ID",
        .rebundleHint: "If you recently re-bundled the app, macOS may treat it as a new app. Re-add it in System Settings → Privacy & Security → Accessibility, then restart CopyGlass.",
        
        .historySubtitle: "Search and paste from clipboard history.",
        .clipboardItems: "Clipboard Items",
        .clipboardItemsSubtitle: "Browse recent copies",
        .clearHistory: "Clear History",
        .clipboardHistory: "Clipboard History",
        .clipboardHistorySubtitle: "Tap an item to paste.",
        
        .quickReplySubtitle: "Reusable snippets you can paste instantly.",
        .quickReplies: "Quick Replies",
        .quickRepliesSubtitle: "Manage your snippets",
        
        .new: "New",
        .delete: "Delete",
        .cancel: "Cancel",
        .save: "Save",
        
        .newQuickReply: "New Quick Reply",
        .title: "Title",
        .shortcutOptional: "Shortcut (optional)",
        
        .aboutSubtitle: "Version and highlights.",
        .version: "Version",
        .platform: "Platform",
        .highlights: "Highlights",
        .highlightHistoryRichText: "Clipboard history with rich text",
        .highlightQuickReplies: "Quick replies with one click paste",
        .highlightMenuBarHotkey: "Menu bar and global shortcut",

        .screenshot: "Screenshot",
        .screenshotSubtitle: "Capture, annotate, recognize text and pin to screen.",
        .screenshotEditor: "Screenshot",
        .screenshotPreferences: "Screenshot Preferences",
        .screenshotPreferencesSubtitle: "Save location and capture behaviour",
        .screenshotAutoCopy: "Copy to clipboard when finishing (Enter)",
        .screenshotShowEditor: "Show the annotation toolbar after selecting",
        .screenshotSaveDirectory: "Save to",
        .screenshotChooseFolder: "Choose…",
        .screenshotAskEveryTime: "Ask every time",
        .screenshotFormat: "Image format",
        .screenshotQuality: "JPEG quality",
        .screenshotCaptureGroup: "Capture",
        .screenshotPinGroup: "Pinned windows",

        .captureRegion: "Capture Region",
        .captureWindow: "Capture Window",
        .captureFullScreen: "Capture Full Screen",
        .captureScrolling: "Scrolling Capture",
        .extractText: "Extract Text",
        .captureAndPin: "Capture and Pin",

        .selectionHintRegion: "Click a window · Drag to select a region · Esc to cancel",
        .selectionHintWindow: "Click a window to capture · Esc to cancel",
        .selectionHintEditing: "Drag to draw · Enter to copy · Esc to cancel",
        .strokeWidth: "Stroke",
        .back: "Back",
        .copiedText: "Text copied",
        .ocrFailed: "Text recognition failed. Please try again.",
        .noTextFound: "No text found",

        .scrollingCaptureTitle: "Scrolling Capture",
        .scrollingCaptureHint: "Scrolls automatically — press Stop to finish.",
        .scrollingCaptureStop: "Stop",
        .scrollingCaptureProgress: "Captured {count} frames · {height} px tall",

        .ocrTitle: "Text Recognition",
        .ocrRecognizing: "Recognizing…",
        .ocrEmpty: "No text found",
        .ocrShowBoxes: "Highlight text areas",
        .copyAll: "Copy All",
        .copy: "Copy",
        .copied: "Copied",
        .copiedToClipboard: "Copied to clipboard",
        .close: "Close",
        .undo: "Undo",
        .redo: "Redo",
        .clear: "Clear",
        .pinned: "Pinned to screen",

        .toolSelect: "Select / Move",
        .toolRectangle: "Rectangle",
        .toolEllipse: "Ellipse",
        .toolArrow: "Arrow",
        .toolPen: "Pen",
        .toolHighlighter: "Highlighter",
        .toolText: "Text",
        .toolMosaic: "Mosaic",
        .toolNumber: "Step number",
        .annotationTextPlaceholder: "Text",

        .pin: "Pin to Screen",
        .pinOpacity: "Opacity",
        .pinResizeToOriginal: "Reset Size",
        .pinUnpinAll: "Unpin All",

        .screenRecording: "Screen Recording",
        .screenRecordingPermissionTitle: "Screen Recording permission required",
        .screenRecordingPermissionMessage: "CopyGlass needs the Screen Recording permission to take screenshots. Grant it in System Settings → Privacy & Security → Screen Recording, then try again.",
        .openSystemSettings: "Open System Settings",
        .screenshotPermissionRequired: "Screen Recording permission is required for screenshots.",
        .screenshotFailed: "Screenshot failed"
    ]
    
    private static let zh: [L10nKey: String] = [
        .general: "通用",
        .history: "历史记录",
        .quickReply: "快捷回复",
        .about: "关于",
        .search: "搜索",
        .shortcut: "快捷键",
        .permissions: "权限",
        .preferences: "偏好设置",
        .appearanceLanguage: "外观与语言",
        .language: "语言",
        .theme: "主题",
        .system: "跟随系统",
        .light: "亮色",
        .dark: "暗色",
        .resetToDefaults: "恢复默认",
        .change: "修改",
        .openAccessibilitySettings: "打开辅助功能设置",
        .enabled: "已启用",
        .disabled: "未启用",
        .enterToCopy: "回车复制",
        .historyList: "历史列表",
        .quickReplyList: "快捷回复列表",
        .showMainWindow: "显示主窗口",
        .quit: "退出",
        
        .generalSubtitle: "CopyGlass 的通用偏好设置。",
        .preferencesSubtitle: "保留与启动行为",
        .hotkeySubtitle: "用快捷键呼出历史列表",
        .permissionsRowSubtitle: "用于自动粘贴的辅助功能权限",
        .appearanceLanguageSubtitle: "主题与语言",
        
        .globalHotkeys: "全局快捷键",
        .hotkeyMustIncludeCmd: "快捷键必须包含 ⌘，避免影响日常输入。",
        .hotkeyAlreadyUsed: "该快捷键已被其他动作使用。",
        .setHotkey: "设置快捷键",
        .pressHotkeyHint: "请按下组合键（必须包含 ⌘），按 Esc 取消。",
        .recording: "录制中…",
        
        .retention: "保留",
        .startup: "启动",
        .keepItemsFor: "保留条目时长",
        .days7: "7 天",
        .days30: "30 天",
        .forever: "永久",
        .startAtLogin: "开机自启",
        
        .accessibility: "辅助功能",
        .status: "状态",
        .requiredForAutoPaste: "自动粘贴需要此权限。",
        .actions: "操作",
        .refreshStatus: "刷新状态",
        .requestPermission: "请求权限",
        .debug: "调试",
        .appPath: "应用路径",
        .bundleId: "Bundle ID",
        .rebundleHint: "如果你最近重新打包了应用，macOS 可能会将其视为新应用。请在 系统设置 → 隐私与安全性 → 辅助功能 中重新添加，然后重启 CopyGlass。",
        
        .historySubtitle: "搜索并粘贴历史剪贴板内容。",
        .clipboardItems: "剪贴板条目",
        .clipboardItemsSubtitle: "浏览最近复制内容",
        .clearHistory: "清空历史记录",
        .clipboardHistory: "剪贴板历史",
        .clipboardHistorySubtitle: "点击条目即可粘贴。",
        
        .quickReplySubtitle: "可快速粘贴的常用文本片段。",
        .quickReplies: "快捷回复列表",
        .quickRepliesSubtitle: "管理你的文本片段",
        
        .new: "新增",
        .delete: "删除",
        .cancel: "取消",
        .save: "保存",
        
        .newQuickReply: "新增快捷回复",
        .title: "标题",
        .shortcutOptional: "快捷键（可选）",
        
        .aboutSubtitle: "版本信息与功能亮点。",
        .version: "版本",
        .platform: "平台",
        .highlights: "亮点",
        .highlightHistoryRichText: "支持富文本的剪贴板历史",
        .highlightQuickReplies: "一键粘贴快捷回复",
        .highlightMenuBarHotkey: "菜单栏与全局快捷键",

        .screenshot: "截图",
        .screenshotSubtitle: "截图、标注、文字识别与固定到屏幕。",
        .screenshotEditor: "截图",
        .screenshotPreferences: "截图设置",
        .screenshotPreferencesSubtitle: "保存位置与截图行为",
        .screenshotAutoCopy: "完成截图时复制到剪贴板（回车）",
        .screenshotShowEditor: "选中区域后显示标注工具栏",
        .screenshotSaveDirectory: "保存到",
        .screenshotChooseFolder: "选择…",
        .screenshotAskEveryTime: "每次询问",
        .screenshotFormat: "图片格式",
        .screenshotQuality: "JPEG 质量",
        .screenshotCaptureGroup: "截图",
        .screenshotPinGroup: "固定窗口",

        .captureRegion: "区域截图",
        .captureWindow: "窗口截图",
        .captureFullScreen: "全屏截图",
        .captureScrolling: "滚动截图",
        .extractText: "提取文字",
        .captureAndPin: "截图并固定",

        .selectionHintRegion: "单击选择窗口 · 拖动选择区域 · Esc 取消",
        .selectionHintWindow: "单击要截取的窗口 · Esc 取消",
        .selectionHintEditing: "拖动绘制 · 回车复制 · Esc 取消",
        .strokeWidth: "粗细",
        .back: "返回",
        .copiedText: "已复制文字",
        .ocrFailed: "文字识别失败，请重试。",
        .noTextFound: "未识别到文字",

        .scrollingCaptureTitle: "滚动截图",
        .scrollingCaptureHint: "正在自动滚动，点击停止结束。",
        .scrollingCaptureStop: "停止",
        .scrollingCaptureProgress: "已捕获 {count} 帧 · 高度 {height} px",

        .ocrTitle: "文字识别",
        .ocrRecognizing: "识别中…",
        .ocrEmpty: "未识别到文字",
        .ocrShowBoxes: "显示文字区域",
        .copyAll: "复制全部",
        .copy: "复制",
        .copied: "已复制",
        .copiedToClipboard: "已复制到剪贴板",
        .close: "关闭",
        .undo: "撤销",
        .redo: "重做",
        .clear: "清空",
        .pinned: "已固定到屏幕",

        .toolSelect: "选择 / 移动",
        .toolRectangle: "矩形",
        .toolEllipse: "椭圆",
        .toolArrow: "箭头",
        .toolPen: "画笔",
        .toolHighlighter: "荧光笔",
        .toolText: "文字",
        .toolMosaic: "马赛克",
        .toolNumber: "序号",
        .annotationTextPlaceholder: "文字",

        .pin: "固定到屏幕",
        .pinOpacity: "不透明度",
        .pinResizeToOriginal: "恢复原始大小",
        .pinUnpinAll: "取消全部固定",

        .screenRecording: "屏幕录制",
        .screenRecordingPermissionTitle: "需要屏幕录制权限",
        .screenRecordingPermissionMessage: "CopyGlass 需要「屏幕录制」权限才能截图。请在 系统设置 → 隐私与安全性 → 屏幕录制 中授权后重试。",
        .openSystemSettings: "打开系统设置",
        .screenshotPermissionRequired: "截图需要屏幕录制权限。",
        .screenshotFailed: "截图失败"
    ]
}
