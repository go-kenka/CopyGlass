import AppKit

final class PaletteWindowController: NSWindowController {
    var keyHandler: ((NSEvent) -> Bool)?
    
    private var monitor: Any?
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        ensureMonitor()
    }
    
    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func ensureMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.window?.isKeyWindow == true else { return event }
            if self.keyHandler?(event) == true {
                return nil
            }
            return event
        }
    }
}

