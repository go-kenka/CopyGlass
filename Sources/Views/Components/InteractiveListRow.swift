import SwiftUI

enum InteractiveListRowStyle {
    static func backgroundOpacity(isHovered: Bool, isSelected: Bool, usesNativeSelection: Bool = false) -> Double {
        if usesNativeSelection { return 0 }
        if isSelected { return 0.22 }
        if isHovered { return 0.10 }
        return 0
    }
}

private struct InteractiveListRowModifier: ViewModifier {
    let isSelected: Bool
    let usesNativeSelection: Bool
    @State private var isHovered = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesNativeSelection {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .listRowBackground(Color.clear)
        } else {
            let opacity = InteractiveListRowStyle.backgroundOpacity(
                isHovered: isHovered,
                isSelected: isSelected
            )
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .listRowBackground((isSelected ? Color.accentColor : Color.primary).opacity(opacity))
        }
    }
}

extension View {
    func interactiveListRow(isSelected: Bool = false, usesNativeSelection: Bool = false) -> some View {
        modifier(InteractiveListRowModifier(isSelected: isSelected, usesNativeSelection: usesNativeSelection))
    }
}
