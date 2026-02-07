import SwiftUI
import Carbon

enum AppSection: String, CaseIterable, Identifiable {
    case general
    case history
    case quickReply
    case about
    
    var id: String { rawValue }
    
    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .general: return L10n.t(.general, lang: lang)
        case .history: return L10n.t(.history, lang: lang)
        case .quickReply: return L10n.t(.quickReply, lang: lang)
        case .about: return L10n.t(.about, lang: lang)
        }
    }
    
    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .history: return "clock.arrow.circlepath"
        case .quickReply: return "text.bubble"
        case .about: return "info.circle"
        }
    }
    
    var iconColors: [Color] {
        switch self {
        case .general: return [Color(red: 0.40, green: 0.55, blue: 1.0), Color(red: 0.20, green: 0.35, blue: 0.95)]
        case .history: return [Color(red: 0.55, green: 0.38, blue: 1.0), Color(red: 0.30, green: 0.20, blue: 0.85)]
        case .quickReply: return [Color(red: 0.15, green: 0.78, blue: 0.75), Color(red: 0.05, green: 0.55, blue: 0.70)]
        case .about: return [Color(red: 0.95, green: 0.55, blue: 0.25), Color(red: 0.95, green: 0.35, blue: 0.25)]
        }
    }
}

struct SettingsView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @State private var selection: AppSection = .general
    @State private var sidebarSearchText: String = ""
    @Environment(\.appLanguage) private var lang
    
    var body: some View {
        NavigationSplitView {
            List(filteredSections, selection: $selection) { section in
                SettingsSidebarRow(title: section.title(lang), iconSystemName: section.systemImage, iconColors: section.iconColors)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .searchable(text: $sidebarSearchText, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                SettingsDetailView(
                    selection: $selection,
                    clipboardManager: clipboardManager
                )
            }
        }
    }
    
    private var filteredSections: [AppSection] {
        if sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppSection.allCases
        }
        let q = sidebarSearchText.lowercased()
        return AppSection.allCases.filter { $0.title(lang).lowercased().contains(q) }
    }
}

struct SettingsDetailView: View {
    @Binding var selection: AppSection
    @ObservedObject var clipboardManager: ClipboardManager
    
    var body: some View {
        NavigationStack {
            switch selection {
            case .general:
                GeneralRootView()
            case .history:
                HistoryRootView(clipboardManager: clipboardManager)
            case .quickReply:
                QuickReplyRootView()
            case .about:
                AboutRootView()
            }
        }
    }
}

struct GeneralRootView: View {
    @Environment(\.appLanguage) private var lang
    var body: some View {
        List {
            Section {
                SettingsHeroCard(
                    title: L10n.t(.general, lang: lang),
                    subtitle: L10n.t(.generalSubtitle, lang: lang),
                    iconSystemName: AppSection.general.systemImage,
                    iconColors: AppSection.general.iconColors
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            }
            
            Section {
                NavigationLink {
                    PreferencesSettingsView()
                        .navigationTitle(L10n.t(.preferences, lang: lang))
                        .detailSurface()
                } label: {
                    SettingsNavigationRow(
                        title: L10n.t(.preferences, lang: lang),
                        subtitle: L10n.t(.preferencesSubtitle, lang: lang),
                        iconSystemName: "slider.horizontal.3",
                        iconColors: [Color(red: 0.20, green: 0.55, blue: 1.0), Color(red: 0.10, green: 0.30, blue: 0.95)]
                    )
                }
                
                NavigationLink {
                    HotkeySettingsView()
                        .navigationTitle(L10n.t(.shortcut, lang: lang))
                } label: {
                    SettingsNavigationRow(
                        title: L10n.t(.shortcut, lang: lang),
                        subtitle: L10n.t(.hotkeySubtitle, lang: lang),
                        iconSystemName: "keyboard",
                        iconColors: [Color(red: 0.55, green: 0.38, blue: 1.0), Color(red: 0.30, green: 0.20, blue: 0.85)]
                    )
                }
                
                NavigationLink {
                    PermissionsSettingsView()
                        .navigationTitle(L10n.t(.permissions, lang: lang))
                } label: {
                    SettingsNavigationRow(
                        title: L10n.t(.permissions, lang: lang),
                        subtitle: L10n.t(.permissionsRowSubtitle, lang: lang),
                        iconSystemName: "hand.raised.fill",
                        iconColors: [Color(red: 0.95, green: 0.55, blue: 0.25), Color(red: 0.95, green: 0.35, blue: 0.25)]
                    )
                }
                
                NavigationLink {
                    AppearanceLanguageSettingsView()
                        .navigationTitle(L10n.t(.appearanceLanguage, lang: lang))
                } label: {
                    SettingsNavigationRow(
                        title: L10n.t(.appearanceLanguage, lang: lang),
                        subtitle: L10n.t(.appearanceLanguageSubtitle, lang: lang),
                        iconSystemName: "paintbrush",
                        iconColors: [Color(red: 0.90, green: 0.62, blue: 0.18), Color(red: 0.86, green: 0.40, blue: 0.10)]
                    )
                }
            }
        }
        .listStyle(.inset)
        .detailSurface()
    }
}

struct AppearanceLanguageSettingsView: View {
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.zhHans.rawValue
    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue
    @Environment(\.appLanguage) private var lang
    
    var body: some View {
        List {
            Section {
                SettingsHeroCard(
                    title: L10n.t(.appearanceLanguage, lang: lang),
                    subtitle: L10n.t(.appearanceLanguageSubtitle, lang: lang),
                    iconSystemName: "paintbrush",
                    iconColors: [Color(red: 0.90, green: 0.62, blue: 0.18), Color(red: 0.86, green: 0.40, blue: 0.10)]
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            }
            
            Section(L10n.t(.language, lang: lang)) {
                Picker("", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { l in
                        Text(languageName(l, lang: lang)).tag(l.rawValue)
                    }
                }
                .labelsHidden()
            }
            
            Section(L10n.t(.theme, lang: lang)) {
                Picker("", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { t in
                        Text(themeName(t, lang: lang)).tag(t.rawValue)
                    }
                }
                .labelsHidden()
            }
        }
        .listStyle(.inset)
        .detailSurface()
    }
    
    private func languageName(_ language: AppLanguage, lang: AppLanguage) -> String {
        switch (language, lang) {
        case (.zhHans, .zhHans): return "中文"
        case (.zhHans, .en): return "Chinese"
        case (.en, .zhHans): return "英文"
        case (.en, .en): return "English"
        }
    }
    
    private func themeName(_ theme: AppTheme, lang: AppLanguage) -> String {
        switch theme {
        case .system: return L10n.t(.system, lang: lang)
        case .light: return L10n.t(.light, lang: lang)
        case .dark: return L10n.t(.dark, lang: lang)
        }
    }
}

struct HistoryRootView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @Environment(\.appLanguage) private var lang
    
    var body: some View {
        List {
            Section {
                SettingsHeroCard(
                    title: L10n.t(.history, lang: lang),
                    subtitle: L10n.t(.historySubtitle, lang: lang),
                    iconSystemName: AppSection.history.systemImage,
                    iconColors: AppSection.history.iconColors
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            }
            
            Section {
                NavigationLink {
                    HistoryItemsView(clipboardManager: clipboardManager)
                        .navigationTitle(L10n.t(.clipboardHistory, lang: lang))
                } label: {
                    SettingsNavigationRow(
                        title: L10n.t(.clipboardItems, lang: lang),
                        subtitle: L10n.t(.clipboardItemsSubtitle, lang: lang),
                        iconSystemName: "list.bullet.rectangle",
                        iconColors: [Color(red: 0.15, green: 0.78, blue: 0.75), Color(red: 0.05, green: 0.55, blue: 0.70)]
                    )
                }
                
                Button(role: .destructive) {
                    clipboardManager.clearHistory()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconBadge(
                            systemName: "trash.fill",
                            colors: [Color(red: 1.0, green: 0.35, blue: 0.38), Color(red: 0.85, green: 0.12, blue: 0.20)],
                            size: 28,
                            cornerRadius: 8
                        )
                        Text(L10n.t(.clearHistory, lang: lang))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.inset)
        .detailSurface()
    }
}

struct HistoryItemsView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @State private var searchText: String = ""
    @Environment(\.appLanguage) private var lang
    
    var body: some View {
        List {
            Section {
                SettingsHeroCard(
                    title: L10n.t(.clipboardHistory, lang: lang),
                    subtitle: L10n.t(.clipboardHistorySubtitle, lang: lang),
                    iconSystemName: "list.bullet.rectangle",
                    iconColors: [Color(red: 0.55, green: 0.38, blue: 1.0), Color(red: 0.30, green: 0.20, blue: 0.85)]
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            }
            
            Section {
                ForEach(filteredHistory) { item in
                    HistoryItemRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { copyItem(item) }
                }
            }
        }
        .listStyle(.inset)
        .searchable(text: $searchText, placement: .toolbar, prompt: L10n.t(.search, lang: lang))
        .detailSurface()
    }
    
    private var filteredHistory: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboardManager.history
        } else {
            return clipboardManager.history.filter { item in
                item.content?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
    
    private func copyItem(_ item: ClipboardItem) {
        clipboardManager.copyToPasteboard(item: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            PasteboardHelper.paste()
            NSApp.hide(nil)
        }
    }
}

struct QuickReplyRootView: View {
    @Environment(\.appLanguage) private var lang
    var body: some View {
        List {
            Section {
                SettingsHeroCard(
                    title: L10n.t(.quickReply, lang: lang),
                    subtitle: L10n.t(.quickReplySubtitle, lang: lang),
                    iconSystemName: AppSection.quickReply.systemImage,
                    iconColors: AppSection.quickReply.iconColors
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            }
            
            Section {
                NavigationLink {
                    QuickReplyView()
                        .navigationTitle(L10n.t(.quickReplies, lang: lang))
                } label: {
                    SettingsNavigationRow(
                        title: L10n.t(.quickReplies, lang: lang),
                        subtitle: L10n.t(.quickRepliesSubtitle, lang: lang),
                        iconSystemName: "text.bubble.fill",
                        iconColors: [Color(red: 0.15, green: 0.78, blue: 0.75), Color(red: 0.05, green: 0.55, blue: 0.70)]
                    )
                }
            }
        }
        .listStyle(.inset)
        .detailSurface()
    }
}

struct AboutRootView: View {
    @Environment(\.appLanguage) private var lang
    var body: some View {
        List {
            Section {
                SettingsHeroCard(
                    title: L10n.t(.about, lang: lang),
                    subtitle: L10n.t(.aboutSubtitle, lang: lang),
                    iconSystemName: AppSection.about.systemImage,
                    iconColors: AppSection.about.iconColors
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            }
            
            Section("CopyGlass") {
                LabeledContent(L10n.t(.version, lang: lang)) { Text("1.0.0") }
                LabeledContent(L10n.t(.platform, lang: lang)) { LiquidGlassChip(text: "macOS") }
            }
            
            Section(L10n.t(.highlights, lang: lang)) {
                Label(L10n.t(.highlightHistoryRichText, lang: lang), systemImage: "sparkles")
                Label(L10n.t(.highlightQuickReplies, lang: lang), systemImage: "bolt.fill")
                Label(L10n.t(.highlightMenuBarHotkey, lang: lang), systemImage: "keyboard")
            }
        }
        .listStyle(.inset)
        .detailSurface()
    }
}

struct HotkeySettingsView: View {
    @StateObject private var store = HotKeySettingsStore.shared
    @State private var recordingAction: HotKeyAction?
    @State private var errorMessage: String?
    @Environment(\.appLanguage) private var lang
    
    var body: some View {
        ZStack {
            List {
                Section {
                    SettingsHeroCard(
                        title: L10n.t(.shortcut, lang: lang),
                        subtitle: L10n.t(.hotkeySubtitle, lang: lang),
                        iconSystemName: "keyboard",
                        iconColors: [Color(red: 0.55, green: 0.38, blue: 1.0), Color(red: 0.30, green: 0.20, blue: 0.85)]
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(Color.clear)
                }
                
                Section(L10n.t(.globalHotkeys, lang: lang)) {
                    ForEach(HotKeyAction.allCases) { action in
                        HStack {
                            Text(action.title(lang: lang))
                            Spacer(minLength: 0)
                            Text(HotKeyFormat.displayString(store.binding(for: action)))
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.12), in: Capsule(style: .continuous))
                            Button(L10n.t(.change, lang: lang)) {
                                recordingAction = action
                                errorMessage = nil
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                Section {
                    Button(L10n.t(.resetToDefaults, lang: lang)) {
                        store.resetToDefaults()
                    }
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.inset)
            .detailSurface()
            
            if let recordingAction {
                HotKeyRecordingOverlay(
                    action: recordingAction,
                    onCancel: {
                        self.recordingAction = nil
                    },
                    onRecord: { event in
                        let modifiers = HotKeyFormat.carbonModifiers(from: event.modifierFlags)
                        if event.keyCode == 53 {
                            self.recordingAction = nil
                            return
                        }
                        if (modifiers & UInt32(cmdKey)) == 0 {
                            self.errorMessage = L10n.t(.hotkeyMustIncludeCmd, lang: lang)
                            self.recordingAction = nil
                            return
                        }
                        let binding = HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
                        if isDuplicate(binding, excluding: recordingAction) {
                            self.errorMessage = L10n.t(.hotkeyAlreadyUsed, lang: lang)
                            self.recordingAction = nil
                            return
                        }
                        store.setBinding(binding, for: recordingAction)
                        self.recordingAction = nil
                    }
                )
            }
        }
    }
    
    private func isDuplicate(_ binding: HotKeyBinding, excluding action: HotKeyAction) -> Bool {
        for a in HotKeyAction.allCases where a != action {
            if store.binding(for: a) == binding { return true }
        }
        return false
    }
}

struct HotKeyRecordingOverlay: View {
    let action: HotKeyAction
    let onCancel: () -> Void
    let onRecord: (NSEvent) -> Void
    @Environment(\.appLanguage) private var lang
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }
            
            VStack(spacing: 12) {
                Text(L10n.t(.setHotkey, lang: lang))
                    .font(.headline)
                Text(action.title(lang: lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(L10n.t(.pressHotkeyHint, lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 10) {
                    Button(L10n.t(.cancel, lang: lang)) { onCancel() }
                    Spacer(minLength: 0)
                    Text(L10n.t(.recording, lang: lang))
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(width: 360)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .background(HotKeyRecorder { event in
                onRecord(event)
            })
        }
    }
}

struct PermissionsSettingsView: View {
    @State private var accessibilityTrusted = PasteboardHelper.accessibilityTrusted(prompt: false)
    @Environment(\.appLanguage) private var lang
    @State private var refreshToken = UUID()
    
    var body: some View {
        List {
            Section {
                SettingsHeroCard(
                    title: L10n.t(.permissions, lang: lang),
                    subtitle: L10n.t(.requiredForAutoPaste, lang: lang),
                    iconSystemName: "hand.raised.fill",
                    iconColors: [Color(red: 0.95, green: 0.55, blue: 0.25), Color(red: 0.95, green: 0.35, blue: 0.25)]
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            }
            
            Section(L10n.t(.accessibility, lang: lang)) {
                LabeledContent(L10n.t(.status, lang: lang)) {
                    LiquidGlassChip(text: accessibilityTrusted ? L10n.t(.enabled, lang: lang) : L10n.t(.disabled, lang: lang), isProminent: !accessibilityTrusted)
                }
                Text(L10n.t(.requiredForAutoPaste, lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section(L10n.t(.actions, lang: lang)) {
                Button(L10n.t(.refreshStatus, lang: lang)) {
                    refreshAccessibilityStatus(poll: true)
                }
                Button(L10n.t(.requestPermission, lang: lang)) {
                    _ = PasteboardHelper.accessibilityTrusted(prompt: true)
                    refreshAccessibilityStatus(poll: true)
                }
                Button(L10n.t(.openAccessibilitySettings, lang: lang)) {
                    PasteboardHelper.openAccessibilitySettings()
                }
            }
            
            Section(L10n.t(.debug, lang: lang)) {
                LabeledContent(L10n.t(.appPath, lang: lang)) {
                    Text(Bundle.main.bundlePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                LabeledContent(L10n.t(.bundleId, lang: lang)) {
                    Text(Bundle.main.bundleIdentifier ?? "-")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(L10n.t(.rebundleHint, lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .detailSurface()
        .onAppear {
            refreshAccessibilityStatus(poll: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus(poll: true)
        }
    }
    
    private func refreshAccessibilityStatus(poll: Bool) {
        accessibilityTrusted = PasteboardHelper.accessibilityTrusted(prompt: false)
        guard poll else { return }
        
        let token = UUID()
        refreshToken = token
        for i in 1...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) {
                guard refreshToken == token else { return }
                accessibilityTrusted = PasteboardHelper.accessibilityTrusted(prompt: false)
            }
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("retentionDays") private var retentionDays = 7
    @AppStorage("autoStart") private var autoStart = false
    @Environment(\.appLanguage) private var lang
    @State private var startAtLoginEnabled = false
    
    var body: some View {
        List {
            Section {
                SettingsHeroCard(
                    title: L10n.t(.preferences, lang: lang),
                    subtitle: L10n.t(.preferencesSubtitle, lang: lang),
                    iconSystemName: "slider.horizontal.3",
                    iconColors: [Color(red: 0.20, green: 0.55, blue: 1.0), Color(red: 0.10, green: 0.30, blue: 0.95)]
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
            }
            
            Section(L10n.t(.retention, lang: lang)) {
                LabeledContent(L10n.t(.keepItemsFor, lang: lang)) {
                    Picker("", selection: $retentionDays) {
                        Text(L10n.t(.days7, lang: lang)).tag(7)
                        Text(L10n.t(.days30, lang: lang)).tag(30)
                        Text(L10n.t(.forever, lang: lang)).tag(36500)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            
            Section(L10n.t(.startup, lang: lang)) {
                Toggle(L10n.t(.startAtLogin, lang: lang), isOn: $startAtLoginEnabled)
            }
        }
        .listStyle(.inset)
        .onAppear {
            startAtLoginEnabled = LoginItemManager.isEnabled()
            if autoStart && !startAtLoginEnabled {
                LoginItemManager.setEnabled(true)
                startAtLoginEnabled = LoginItemManager.isEnabled()
            }
        }
        .onChange(of: startAtLoginEnabled) { _, newValue in
            autoStart = newValue
            LoginItemManager.setEnabled(newValue)
            startAtLoginEnabled = LoginItemManager.isEnabled()
        }
    }
}

typealias PreferencesSettingsView = GeneralSettingsView

struct AboutView: View {
    @Environment(\.appLanguage) private var lang
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .liquidGlassIfAvailable(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CopyGlass")
                            .font(.headline)
                        Text("\(L10n.t(.version, lang: lang)) 1.0.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer(minLength: 0)
                    
                    LiquidGlassChip(text: "macOS")
                }
            }
            
            GroupBox(L10n.t(.highlights, lang: lang)) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L10n.t(.highlightHistoryRichText, lang: lang), systemImage: "sparkles")
                    Label(L10n.t(.highlightQuickReplies, lang: lang), systemImage: "bolt.fill")
                    Label(L10n.t(.highlightMenuBarHotkey, lang: lang), systemImage: "keyboard")
                }
                .font(.subheadline)
            }
            
            Spacer(minLength: 0)
        }
    }
}
