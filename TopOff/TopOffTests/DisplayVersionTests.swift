import XCTest
@testable import TopOff

final class DisplayVersionTests: XCTestCase {

    func testExtractsSemverFromVersionWithShaSuffix() {
        let input = "1.9255.0,a22af1fabbbc85af5502e695ed8fbea9f74276fc"
        XCTAssertEqual(DisplayVersion.abbreviate(input), "1.9255.0")
    }

    func testExtractsSemverFromVersionWithShortBuildSuffix() {
        XCTAssertEqual(DisplayVersion.abbreviate("4.75.0,227598"), "4.75.0")
    }

    func testExtractsSemverFromVersionWithNumericSuffix() {
        XCTAssertEqual(DisplayVersion.abbreviate("1.0,12345678"), "1.0")
    }

    func testIgnoresDownloadSizeSavedBeforeTheFix() {
        XCTAssertEqual(DisplayVersion.abbreviate("9.1            (22.3MB)"), "9.1")
        XCTAssertEqual(DisplayVersion.abbreviate("12.23.0        (24MB)"), "12.23.0")
    }

    func testLeavesCleanSemverUnchanged() {
        XCTAssertEqual(DisplayVersion.abbreviate("126.3.12"), "126.3.12")
    }

    func testPassesPlaceholderThrough() {
        XCTAssertEqual(DisplayVersion.abbreviate("?"), "?")
    }

    func testExtractsLongestDottedRunFromDateStampVersion() {
        // The full dotted run wins; the trailing alphanumeric `.stable_03`
        // tail is dropped because it isn't part of a `\d+(?:\.\d+)+` match.
        let input = "0.2026.05.20.09.21.stable_03"
        XCTAssertEqual(DisplayVersion.abbreviate(input), "0.2026.05.20.09.21")
    }

    func testExtractsSemverFromMultiCommaVersion() {
        let input = "1.0,a22af1fabbbc85af5502e695ed8fbea9,extra"
        XCTAssertEqual(DisplayVersion.abbreviate(input), "1.0")
    }

    func testExtractsSemverBuriedBetweenMetadata() {
        // The omnissa-horizon-client case that motivated the rewrite:
        // year-month prefix, build number suffix, and bracketed metadata
        // after a comma, with the real product version in the middle.
        let input = "2506-8.16.0-16536825094,CART26FQ2_MAC_2506"
        XCTAssertEqual(DisplayVersion.abbreviate(input), "8.16.0")
    }

    func testFallsBackToFirstSegmentWhenNoDottedRun() {
        // Nothing matches `\d+(?:\.\d+)+`, so the fallback returns the
        // substring before the first comma.
        XCTAssertEqual(DisplayVersion.abbreviate("alpha,beta"), "alpha")
    }

    func testIdempotent() {
        let once = DisplayVersion.abbreviate("1.9255.0,a22af1fabbbc85af5502e695ed8fbea9f74276fc")
        let twice = DisplayVersion.abbreviate(once)
        XCTAssertEqual(once, twice)
    }
}
