import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

enum LoginItemManager {
    private static var label: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "copyglass"
        return "\(bundleID).launchAtLogin"
    }
    
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }
    
    static func isEnabled() -> Bool {
#if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
#endif
        let uid = String(getuid())
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "gui/\(uid)/\(label)"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    static func setEnabled(_ enabled: Bool) {
#if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
            }
            return
        }
#endif
        if enabled {
            enable()
        } else {
            disable()
        }
    }
    
    private static func enable() {
        do {
            try writePlist()
            try bootoutIfNeeded()
            try bootstrap()
        } catch {
        }
    }
    
    private static func disable() {
        do {
            try bootoutIfNeeded()
            try? FileManager.default.removeItem(at: plistURL)
        } catch {
        }
    }
    
    private static func writePlist() throws {
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let openURL = URL(fileURLWithPath: "/usr/bin/open")
        let bundlePath = Bundle.main.bundlePath
        
        let plist: [String: Any] = [
            "Label": label,
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "ProgramArguments": [openURL.path, "-a", bundlePath]
        ]
        
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: [.atomic])
    }
    
    private static func bootstrap() throws {
        let uid = String(getuid())
        try runLaunchCtl(["bootstrap", "gui/\(uid)", plistURL.path])
    }
    
    private static func bootoutIfNeeded() throws {
        let uid = String(getuid())
        _ = try? runLaunchCtl(["bootout", "gui/\(uid)", plistURL.path])
    }
    
    @discardableResult
    private static func runLaunchCtl(_ args: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            throw NSError(domain: "LoginItemManager", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])
        }
        return output
    }
}
