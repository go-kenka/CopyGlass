import SwiftUI
import AppKit

struct HotKeyRecorder: NSViewRepresentable {
    let onKey: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyPressCatcherView()
        view.onKeyDown = { event in
            onKey(event)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

