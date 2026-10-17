import Foundation
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

extension AppLanguage {
    /// Language currently selected in preferences (usable outside SwiftUI).
    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.zhHans.rawValue
        return AppLanguage(rawValue: raw) ?? .zhHans
    }
}

extension ScreenshotImageFormat {
    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        }
    }
}

/// Persisted screenshot preferences.
enum ScreenshotDefaults {
    static let autoCopyKey = "screenshot.autoCopy"
    static let showEditorKey = "screenshot.showEditor"
    static let formatKey = "screenshot.format"
    static let jpegQualityKey = "screenshot.jpegQuality"
    static let saveDirectoryKey = "screenshot.saveDirectory"

    static func register() {
        UserDefaults.standard.register(defaults: [
            autoCopyKey: true,
            showEditorKey: true,
            formatKey: ScreenshotImageFormat.png.rawValue,
            jpegQualityKey: 0.9
        ])
    }

    static var autoCopy: Bool { UserDefaults.standard.bool(forKey: autoCopyKey) }
    static var showEditor: Bool { UserDefaults.standard.bool(forKey: showEditorKey) }

    static var format: ScreenshotImageFormat {
        ScreenshotImageFormat(rawValue: UserDefaults.standard.string(forKey: formatKey) ?? "png") ?? .png
    }

    static var quality: Double {
        let value = UserDefaults.standard.double(forKey: jpegQualityKey)
        return value > 0 ? value : 0.9
    }

    static var saveDirectory: URL? {
        guard let path = UserDefaults.standard.string(forKey: saveDirectoryKey), !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// Clipboard helpers shared by the editor and pinned windows.
enum ScreenshotClipboard {
    static func copy(image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        if let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = rep.representation(using: .tiff, properties: [:]) {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    static func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Saves screenshots either to the configured folder or through a save panel.
enum ScreenshotSaver {
    static func suggestedFileName(format: ScreenshotImageFormat = ScreenshotDefaults.format) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "CopyGlass-" + formatter.string(from: Date()) + "." + format.fileExtension
    }

    static func write(image: CGImage, to url: URL) throws {
        let format = ScreenshotImageFormat(rawValue: url.pathExtension.lowercased()) ?? ScreenshotDefaults.format
        guard let data = ImageUtils.encode(image, format: format, quality: ScreenshotDefaults.quality) else {
            throw NSError(domain: "CopyGlass", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法生成图片数据"])
        }
        try data.write(to: url, options: .atomic)
    }

    static func save(image: CGImage, suggestedName: String? = nil, window: NSWindow? = nil) {
        let format = ScreenshotDefaults.format
        if let directory = ScreenshotDefaults.saveDirectory {
            let name = suggestedName ?? suggestedFileName(format: format)
            let url = uniqueURL(in: directory, fileName: name)
            do {
                try write(image: image, to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                present(error)
            }
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = suggestedName ?? suggestedFileName(format: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try write(image: image, to: url)
            } catch {
                present(error)
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    private static func uniqueURL(in directory: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(index).\(ext)")
            index += 1
        }
        return candidate
    }

    static func present(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "保存失败 / Save failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
