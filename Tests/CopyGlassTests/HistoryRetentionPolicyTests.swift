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
}
