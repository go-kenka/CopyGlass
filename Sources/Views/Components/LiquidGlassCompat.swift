import SwiftUI

enum LiquidGlassStyle {
    case regular
    case clear
    case identity
}

extension View {
    @ViewBuilder
    func liquidGlassIfAvailable() -> some View {
        #if COPYGLASS_ENABLE_LIQUID_GLASS
        if #available(macOS 26.0, *) {
            glassEffect()
        } else {
            self
        }
        #else
        self
        #endif
    }
    
    @ViewBuilder
    func liquidGlassIfAvailable<S: Shape>(_ style: LiquidGlassStyle, in shape: S) -> some View {
        #if COPYGLASS_ENABLE_LIQUID_GLASS
        if #available(macOS 26.0, *) {
            switch style {
            case .regular:
                glassEffect(.regular, in: shape)
            case .clear:
                glassEffect(.clear, in: shape)
            case .identity:
                glassEffect(.identity, in: shape)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
    
    @ViewBuilder
    func backgroundExtensionIfAvailable() -> some View {
        #if COPYGLASS_ENABLE_LIQUID_GLASS
        if #available(macOS 26.0, *) {
            backgroundExtensionEffect()
        } else {
            self
        }
        #else
        self
        #endif
    }
}

struct LiquidGlassChip: View {
    let text: String
    var isProminent: Bool = false
    
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassIfAvailable(isProminent ? .regular : .clear, in: Capsule(style: .continuous))
            .background {
                #if COPYGLASS_ENABLE_LIQUID_GLASS
                if #available(macOS 26.0, *) {
                    Color.clear
                } else {
                    Capsule(style: .continuous)
                        .fill(.thinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        }
                }
                #else
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    }
                #endif
            }
    }
}
