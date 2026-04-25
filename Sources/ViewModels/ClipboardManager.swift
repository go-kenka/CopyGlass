import Foundation
import AppKit

class ClipboardManager: ObservableObject {
    @Published var history: [ClipboardItem] = []
    private var lastChangeCount: Int
    private var timer: Timer?
    private let store = ClipboardItemStore.shared
    private let maxInMemoryItems = 500
    private let maxOnDiskItems = 5000
    
    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
        store.pruneExpiredItems()
        history = store.fetchRecent(limit: maxInMemoryItems)
        NotificationCenter.default.addObserver(self, selector: #selector(retentionSettingsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func startMonitoring() {
        // Invalidate existing timer if any
        timer?.invalidate()
        // Use common run loop mode to avoid stopping during scroll, but be careful with performance
        timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    @objc private func timerFired() {
        checkPasteboard()
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            copyFromPasteboard(pasteboard)
        }
    }
    
    private func copyFromPasteboard(_ pasteboard: NSPasteboard) {
        var newItem: ClipboardItem?
        let now = Date()
        
        // Priority: RTF > String > Image
        // Note: Many apps put both String and RTF. We prefer RTF for content but keep String for preview.
        
        if let rtfData = pasteboard.data(forType: .rtf) {
            let string = pasteboard.string(forType: .string)
            newItem = ClipboardItem(type: .rtf, content: string, rtfData: rtfData, date: now)
        } else if let string = pasteboard.string(forType: .string) {
            // Check if it's a file URL? For now just text.
            newItem = ClipboardItem(type: .text, content: string, date: now)
        } else if let imgData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            newItem = ClipboardItem(type: .image, imageData: imgData, date: now)
        }
        
        if let item = newItem {
            // Check for duplicates
            if let last = history.first, isDuplicate(item, last) {
                return
            }
            
            DispatchQueue.main.async {
                self.history.insert(item, at: 0)
                if self.history.count > self.maxInMemoryItems {
                    self.history.removeLast(self.history.count - self.maxInMemoryItems)
                }
                self.store.upsert(item)
                self.store.pruneExpiredItems()
                self.store.prune(keep: self.maxOnDiskItems)
            }
        }
    }

    @objc private func retentionSettingsChanged() {
        store.pruneExpiredItems()
        history = store.fetchRecent(limit: maxInMemoryItems)
    }
    
    private func isDuplicate(_ new: ClipboardItem, _ old: ClipboardItem) -> Bool {
        if new.type != old.type { return false }
        switch new.type {
        case .text:
            return new.content == old.content
        case .rtf:
            // Compare content string for RTF too, as RTF data might differ slightly metadata-wise
            return new.content == old.content
        case .image:
            return new.imageData == old.imageData
        default:
            return false
        }
    }
    
    func clearHistory() {
        history.removeAll()
        store.clear()
    }
    
    // Function to paste an item back to clipboard
    func copyToPasteboard(item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            if let content = item.content {
                pasteboard.setString(content, forType: .string)
            }
        case .rtf:
            if let data = item.rtfData {
                pasteboard.setData(data, forType: .rtf)
            }
            // Also set string representation
            if let content = item.content {
                pasteboard.setString(content, forType: .string)
            }
        case .image:
            if let data = item.imageData {
                pasteboard.setData(data, forType: .tiff)
            }
        default:
            break
        }
        
        // Update change count so we don't re-capture our own paste immediately?
        // Actually, if we paste, we *do* want it at the top of history usually, or maybe not.
        // For now let it be re-captured or handle it via a flag.
        // We update lastChangeCount to ignore this change if we don't want to duplicate it.
        lastChangeCount = pasteboard.changeCount
    }
}
