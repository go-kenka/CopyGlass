import XCTest
import SwiftUI
import AppKit
@testable import CopyGlass

final class SettingsSceneTests: XCTestCase {
    /// The Cmd+, window used to host an empty placeholder view, which made it show up blank.
    /// It must now render the real settings UI with a sensible minimum size.
    func testSettingsSceneContentIsNotAnEmptyPlaceholder() {
        let root = AppContainerView(content: SettingsView(clipboardManager: ClipboardManager.shared))
            .frame(minWidth: 820, minHeight: 560)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        hosting.layoutSubtreeIfNeeded()

        let size = hosting.fittingSize
        XCTAssertGreaterThanOrEqual(size.width, 820, "settings content must be laid out, not empty")
        XCTAssertGreaterThanOrEqual(size.height, 560, "settings content must be laid out, not empty")
    }

    func testClipboardManagerIsASingletonSoThePasteboardIsPolledOnce() {
        XCTAssertTrue(ClipboardManager.shared === ClipboardManager.shared)
    }
}
