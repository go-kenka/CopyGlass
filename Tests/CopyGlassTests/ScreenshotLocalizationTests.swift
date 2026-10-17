import XCTest
@testable import CopyGlass

final class LocalizationTests: XCTestCase {
    func testEveryKeyIsTranslatedInBothLanguages() {
        for key in L10nKey.allCases {
            for language in AppLanguage.allCases {
                let value = L10n.t(key, lang: language)
                XCTAssertFalse(value.isEmpty, "empty translation for \(key.rawValue) in \(language.rawValue)")
                XCTAssertNotEqual(
                    value,
                    key.rawValue,
                    "missing \(language.rawValue) translation for \(key.rawValue)"
                )
            }
        }
    }

    func testScreenshotHotKeysAreRegisteredWithDistinctIDs() {
        let ids = HotKeyAction.allCases.map { $0.registrationID }
        XCTAssertEqual(Set(ids).count, ids.count, "hotkey registration ids must be unique")
        XCTAssertEqual(HotKeyAction.allCases.count, 8)
    }

    func testScreenshotPreferencesHaveDefaults() {
        let defaults = UserDefaults.standard
        let originalAutoCopy = defaults.object(forKey: ScreenshotDefaults.autoCopyKey)
        let originalShowEditor = defaults.object(forKey: ScreenshotDefaults.showEditorKey)
        defaults.removeObject(forKey: ScreenshotDefaults.autoCopyKey)
        defaults.removeObject(forKey: ScreenshotDefaults.showEditorKey)
        ScreenshotDefaults.register()

        XCTAssertTrue(ScreenshotDefaults.autoCopy)
        XCTAssertTrue(ScreenshotDefaults.showEditor)
        XCTAssertEqual(ScreenshotDefaults.format, .png)
        XCTAssertGreaterThan(ScreenshotDefaults.quality, 0)

        if let originalAutoCopy {
            defaults.set(originalAutoCopy, forKey: ScreenshotDefaults.autoCopyKey)
        }
        if let originalShowEditor {
            defaults.set(originalShowEditor, forKey: ScreenshotDefaults.showEditorKey)
        }
    }

    func testImageFormatMetadata() {
        XCTAssertEqual(ScreenshotImageFormat.png.fileExtension, "png")
        XCTAssertEqual(ScreenshotImageFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(ScreenshotImageFormat.tiff.bitmapFileType, .tiff)
    }
}
