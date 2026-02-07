import SwiftUI

struct DetailSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            }
    }
}

extension View {
    func detailSurface() -> some View {
        modifier(DetailSurfaceModifier())
    }
}

