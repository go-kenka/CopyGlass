import Carbon
import AppKit

// Global handler function to avoid closure capturing issues with C API
private func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if status == noErr {
        HotKeyManager.shared.handleHotKey(id: hotKeyID.id, signature: hotKeyID.signature)
    }
    return noErr
}

class HotKeyManager {
    static let shared = HotKeyManager()
    
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private let signature: OSType = OSType(0x43475048) // 'CGPH'
    
    private init() {}
    
    func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        ensureEventHandlerInstalled()
        unregisterHotKey(id: id)
        
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard regStatus == noErr, let hotKeyRef else {
            return
        }
        
        hotKeyRefs[id] = hotKeyRef
        handlers[id] = handler
    }
    
    func unregisterHotKey(id: UInt32) {
        if let hotKeyRef = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(hotKeyRef)
        }
        handlers.removeValue(forKey: id)
    }
    
    func unregisterAll() {
        hotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        handlers.removeAll()
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
    
    fileprivate func handleHotKey(id: UInt32, signature: OSType) {
        guard signature == self.signature else { return }
        handlers[id]?()
    }
    
    private func ensureEventHandlerInstalled() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, &eventHandlerRef)
    }
}
