import Foundation
import Carbon
import AppKit

enum HotKeyAction: String, CaseIterable, Codable, Identifiable {
    case toggleMainWindow
    case showHistoryPalette
    case showQuickReplyPalette
    
    var id: String { rawValue }
    
    func title(lang: AppLanguage) -> String {
        L10n.t(l10nKey, lang: lang)
    }
    
    private var l10nKey: L10nKey {
        switch self {
        case .toggleMainWindow: return .showMainWindow
        case .showHistoryPalette: return .historyList
        case .showQuickReplyPalette: return .quickReplyList
        }
    }
    
    var defaultBinding: HotKeyBinding {
        switch self {
        case .toggleMainWindow:
            return HotKeyBinding(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey))
        case .showHistoryPalette:
            return HotKeyBinding(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey))
        case .showQuickReplyPalette:
            return HotKeyBinding(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey))
        }
    }
    
    var registrationID: UInt32 {
        switch self {
        case .toggleMainWindow: return 1
        case .showHistoryPalette: return 2
        case .showQuickReplyPalette: return 3
        }
    }
}

struct HotKeyBinding: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
}

final class HotKeySettingsStore: ObservableObject {
    static let shared = HotKeySettingsStore()
    
    @Published private(set) var bindings: [HotKeyAction: HotKeyBinding] = [:]
    
    private let storageKey = "hotkeys.bindings.v1"
    
    private init() {
        load()
        ensureDefaults()
    }
    
    func binding(for action: HotKeyAction) -> HotKeyBinding {
        bindings[action] ?? action.defaultBinding
    }
    
    func setBinding(_ binding: HotKeyBinding, for action: HotKeyAction) {
        bindings[action] = binding
        save()
        NotificationCenter.default.post(name: .hotKeySettingsChanged, object: nil)
        objectWillChange.send()
    }
    
    func resetToDefaults() {
        bindings = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultBinding) })
        save()
        NotificationCenter.default.post(name: .hotKeySettingsChanged, object: nil)
        objectWillChange.send()
    }
    
    private func ensureDefaults() {
        var updated = bindings
        for action in HotKeyAction.allCases {
            if updated[action] == nil {
                updated[action] = action.defaultBinding
            }
        }
        bindings = updated
        save()
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([HotKeyAction: HotKeyBinding].self, from: data) else { return }
        bindings = decoded
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

extension Notification.Name {
    static let hotKeySettingsChanged = Notification.Name("HotKeySettingsChanged")
}

enum HotKeyFormat {
    static func modifierSymbols(modifiers: UInt32) -> String {
        var parts: [String] = []
        if (modifiers & UInt32(cmdKey)) != 0 { parts.append("⌘") }
        if (modifiers & UInt32(optionKey)) != 0 { parts.append("⌥") }
        if (modifiers & UInt32(controlKey)) != 0 { parts.append("⌃") }
        if (modifiers & UInt32(shiftKey)) != 0 { parts.append("⇧") }
        return parts.joined()
    }
    
    static func keyLabel(keyCode: UInt32) -> String {
        if let label = keyCodeToLabel[keyCode] {
            return label
        }
        return "Key\(keyCode)"
    }
    
    static func displayString(_ binding: HotKeyBinding) -> String {
        "\(modifierSymbols(modifiers: binding.modifiers))\(keyLabel(keyCode: binding.keyCode))"
    }
    
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }
    
    private static let keyCodeToLabel: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓"
    ]
}
