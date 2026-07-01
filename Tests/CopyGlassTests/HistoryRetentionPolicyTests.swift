import XCTest
@testable import CopyGlass

final class HistoryRetentionPolicyTests: XCTestCase {
    func testCutoffDateForSevenDayRetention() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

        let cutoff = HistoryRetentionPolicy.cutoffDate(retentionDays: 7, now: referenceDate)

        XCTAssertEqual(cutoff, referenceDate.addingTimeInterval(-7 * 24 * 60 * 60))
    }

    func testCutoffDateIsNilForForeverRetention() {
        let cutoff = HistoryRetentionPolicy.cutoffDate(retentionDays: 36_500, now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertNil(cutoff)
    }

    func testRetainedRecentQueryDoesNotUseOrPredicate() {
        let sql = ClipboardItemStoreSQL.fetchRecent(summary: true, filteredByRetention: true)

        XCTAssertTrue(sql.contains("WHERE date >= ?"))
        XCTAssertFalse(sql.contains("OR date"))
    }

    func testUnfilteredRecentQueryDoesNotAddRetentionPredicate() {
        let sql = ClipboardItemStoreSQL.fetchRecent(summary: true, filteredByRetention: false)

        XCTAssertFalse(sql.contains("WHERE"))
    }

    func testSearchQueryUsesFTSMatchInsteadOfLike() {
        let sql = ClipboardItemStoreSQL.search(summary: true, filteredByRetention: true)

        XCTAssertTrue(sql.contains("clipboard_items_fts MATCH ?"))
        XCTAssertFalse(sql.localizedCaseInsensitiveContains("LIKE"))
    }

    func testFTSSchemaCreatesVirtualTable() {
        let sql = ClipboardItemStoreSQL.createFTSTable

        XCTAssertTrue(sql.contains("CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts"))
        XCTAssertTrue(sql.contains("USING fts5"))
        XCTAssertTrue(sql.contains("content='clipboard_items'"))
    }

    func testFTSQueryEscapesDoubleQuotes() {
        let query = ClipboardItemStoreSQL.ftsQuery(for: #"hello "quoted""#)

        XCTAssertEqual(query, #""hello"* "quoted"*"#)
    }

    func testHistoryDateFormatterUsesFullTimestamp() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone.current
        components.year = 2026
        components.month = 6
        components.day = 1
        components.hour = 0
        components.minute = 1
        components.second = 2
        let date = try XCTUnwrap(components.date)

        XCTAssertEqual(HistoryDateFormatter.string(from: date), "2026-06-01 00:01:02")
    }

    func testHistoryPaletteMoveSelectionRequestsListFocus() {
        let first = UUID()
        let second = UUID()
        let model = HistoryPaletteModel()
        model.filteredIDs = [first, second]
        model.selectedID = first

        model.moveSelection(delta: 1)

        XCTAssertEqual(model.selectedID, second)
        XCTAssertEqual(model.listFocusRequest, 1)
    }

    func testHistoryPaletteSearchFocusRequestIncrements() {
        let model = HistoryPaletteModel()

        model.focusSearchField()

        XCTAssertEqual(model.searchFocusRequest, 1)
    }

    func testClipboardItemSummaryUsesPreviewOnly() {
        let item = ClipboardItem(
            id: UUID(),
            type: .text,
            content: String(repeating: "x", count: 500),
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let summary = ClipboardItemStore.summary(for: item)

        XCTAssertEqual(summary.id, item.id)
        XCTAssertEqual(summary.type, .text)
        XCTAssertEqual(summary.previewText?.count, 360)
        XCTAssertNil(summary.thumbnailData)
    }

    func testOversizedClipboardImagesAreSkipped() {
        XCTAssertTrue(ClipboardManager.shouldStoreImageData(byteCount: ClipboardManager.maxStoredImageBytes))
        XCTAssertFalse(ClipboardManager.shouldStoreImageData(byteCount: ClipboardManager.maxStoredImageBytes + 1))
    }

    func testOversizedImagePruneDeletesOnlyLargeImages() {
        let sql = ClipboardItemStoreSQL.pruneOversizedImages

        XCTAssertTrue(sql.contains("type = 'image'"))
        XCTAssertTrue(sql.contains("length(image) > ?"))
    }

    func testDatabaseVacuumIsLowFrequencyAndOnlyForLargeFreeSpace() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(AppDatabase.shouldVacuum(pageCount: 100_000, freelistCount: 40_000, pageSize: 4096, lastVacuumAt: nil, now: now))
        XCTAssertFalse(AppDatabase.shouldVacuum(pageCount: 100_000, freelistCount: 40_000, pageSize: 4096, lastVacuumAt: now.addingTimeInterval(-60 * 60), now: now))
        XCTAssertFalse(AppDatabase.shouldVacuum(pageCount: 100_000, freelistCount: 10_000, pageSize: 4096, lastVacuumAt: nil, now: now))
    }

    func testInteractiveListRowFeedbackPrefersSelectionOverHover() {
        XCTAssertEqual(InteractiveListRowStyle.backgroundOpacity(isHovered: false, isSelected: false), 0)
        XCTAssertEqual(InteractiveListRowStyle.backgroundOpacity(isHovered: true, isSelected: false), 0.10)
        XCTAssertEqual(InteractiveListRowStyle.backgroundOpacity(isHovered: true, isSelected: true), 0.22)
    }

    func testInteractiveListRowDoesNotDoubleHighlightNativeSelection() {
        XCTAssertEqual(
            InteractiveListRowStyle.backgroundOpacity(isHovered: true, isSelected: true, usesNativeSelection: true),
            0
        )
    }

    func testInteractiveListRowDoesNotAddHoverLayerToNativeSelectionRows() {
        XCTAssertEqual(
            InteractiveListRowStyle.backgroundOpacity(isHovered: true, isSelected: false, usesNativeSelection: true),
            0
        )
    }
}
