import XCTest
import CoreGraphics
import AppKit
@testable import CopyGlass

final class WindowHitTesterTests: XCTestCase {
    private let defaultFrame = CGRect(x: 100, y: 100, width: 400, height: 300)

    private func capturable(
        layer: Int = 0,
        alpha: Double = 1,
        frame: CGRect? = nil,
        ownerPID: pid_t = 4242,
        ownerName: String = "MyGo Music",
        bundle: String? = "dev.egoist.music",
        ownPID: pid_t = 1
    ) -> Bool {
        WindowHitTester.isCapturable(
            layer: layer,
            alpha: alpha,
            cocoaFrame: frame ?? defaultFrame,
            ownerPID: ownerPID,
            ownerName: ownerName,
            ownerBundleIdentifier: bundle,
            ownPID: ownPID
        )
    }

    func testNormalWindowsAreCapturable() {
        XCTAssertTrue(capturable(layer: 0))
    }

    func testFloatingWindowsAndPopupsAreCapturable() {
        // Regression: a music mini player sits at layer 27, above the menu bar, and used to be
        // silently filtered out by the old `layer == 0` check.
        XCTAssertTrue(capturable(layer: 27))
        XCTAssertTrue(capturable(layer: 3, ownerName: "Translation", bundle: "com.example.translate"))
        XCTAssertTrue(capturable(layer: 8, ownerName: "Dialog", bundle: nil))
        XCTAssertTrue(capturable(layer: 1000, ownerName: "Sticky Notes", bundle: "com.example.sticky"))
    }

    func testDesktopWidgetsAndWallpaperAreNotCapturable() {
        XCTAssertFalse(capturable(layer: -2_147_483_601, ownerName: "通知中心", bundle: "com.apple.notificationcenterui"))
        XCTAssertFalse(capturable(layer: -1))
    }

    func testSystemChromeIsNotCapturable() {
        XCTAssertFalse(capturable(layer: 20, ownerName: "Dock", bundle: "com.apple.dock"))
        XCTAssertFalse(capturable(layer: 21, ownerName: "通知中心", bundle: "com.apple.notificationcenterui"))
        XCTAssertFalse(capturable(layer: 24, ownerName: "Window Server", bundle: nil))
        XCTAssertFalse(capturable(layer: 25, ownerName: "Control Center", bundle: "com.apple.controlcenter"))
        // Localised Dock names are covered by the bundle identifier.
        XCTAssertFalse(capturable(layer: 20, ownerName: "程序坞", bundle: "com.apple.dock"))
    }

    func testOwnWindowsAreNotCapturable() {
        XCTAssertFalse(capturable(ownerPID: 99, ownPID: 99))
    }

    func testInvisibleOrTinyWindowsAreNotCapturable() {
        XCTAssertFalse(capturable(alpha: 0))
        XCTAssertFalse(capturable(alpha: 0.005))
        XCTAssertFalse(capturable(frame: CGRect(x: 0, y: 0, width: 23, height: 300)))
        XCTAssertFalse(capturable(frame: CGRect(x: 0, y: 0, width: 300, height: 10)))
    }
}
