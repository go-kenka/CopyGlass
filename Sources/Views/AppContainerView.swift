import SwiftUI

struct AppContainerView<Content: View>: View {
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.zhHans.rawValue
    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue
    
    let content: Content
    
    var body: some View {
        content
            .environment(\.appLanguage, AppLanguage(rawValue: appLanguage) ?? .zhHans)
            .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
    }
}

