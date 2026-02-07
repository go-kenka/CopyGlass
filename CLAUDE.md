# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

CopyGlass 是一个采用 Liquid Glass 设计风格（半透明毛玻璃效果）的 macOS 剪切板管理工具，使用 Swift 和 SwiftUI 开发。主要功能包括剪切板历史记录管理和快捷回复管理，通过菜单栏图标和全局快捷键访问。

## 构建与运行命令

### 构建应用

在项目根目录执行以下命令：

```bash
cd CopyGlass
swift build --disable-sandbox
```

### 打包为 .app 文件

在项目根目录执行：

```bash
./bundle_app.sh
```

这将生成可运行的 `CopyGlass.app` 应用程序。

## 代码架构

### 核心组件

1. **App 主入口**
   - `CopyGlassApp.swift`：应用程序入口点
   - `AppDelegate`：应用程序代理，初始化状态栏控制器

2. **系统集成**
   - `StatusBarController`：管理菜单栏图标、菜单和窗口控制
   - `HotKeyManager`：全局快捷键注册和处理

3. **数据管理**
   - `ClipboardManager`：监听和管理剪切板变化
   - `ClipboardItemStore`：剪切板历史项的存储和检索
   - `QuickReplyStore`：快捷回复项的存储和管理

4. **UI 组件**
   - `HistoryView`：显示剪切板历史记录
   - `QuickReplyView`：管理快捷回复条目
   - `SettingsView`：应用程序设置
   - `PaletteViews`：快速访问剪切板和快捷回复的特殊视图

### 数据流

1. `ClipboardManager` 监听系统剪切板变化，当检测到新内容时保存到 `ClipboardItemStore`
2. 用户可以通过全局快捷键或菜单栏图标打开不同的视图（设置、历史记录、快捷回复）
3. 当用户从历史记录或快捷回复中选择一项时，内容会复制到系统剪切板

### 特殊功能

1. **Liquid Glass UI 风格**：
   - 使用 `AppContainerView` 提供半透明背景效果
   - 窗口设置包括 `window.backgroundColor = .clear` 和 `window.isOpaque = false` 以实现透明效果

2. **全局快捷键**：
   - 通过 `HotKeyManager` 和 `Carbon` 框架实现跨应用程序快捷键支持
   - 在 `StatusBarController` 中注册和处理快捷键事件

3. **浮动面板**：
   - 使用 `NSPanel` 创建特殊的浮动窗口用于快速访问功能
   - 支持键盘导航和选择

## 技术栈

- 语言：Swift 5.x
- 最低支持：macOS 14 (Sonoma)
- UI 框架：SwiftUI 与 AppKit 混合
- 数据存储：SQLite（通过 `libsqlite3` 链接）
- 系统集成：AppKit、Carbon 框架（用于全局快捷键）

## 注意事项

1. 应用需要辅助功能权限才能实现自动粘贴功能
2. 图标是通过 `GenerateAppIcon.swift` 工具生成的
3. 此应用是 "LSUIElement" 类型，意味着它不在 Dock 中显示图标，主要通过菜单栏访问