import XCTest
@testable import TopOff

@MainActor
final class BrewServiceTests: XCTestCase {

    func testBrewPathExists() {
        let service = BrewService()
        XCTAssertNotNil(service.brewPath, "Brew path should be found")
    }

    func testFindBrewPathAppleSilicon() {
        let service = BrewService()
        let path = service.findBrewPath()
        // Should find either Apple Silicon or Intel path
        XCTAssertTrue(
            path == "/opt/homebrew/bin/brew" || path == "/usr/local/bin/brew",
            "Should find valid brew path"
        )
    }

    func testPermissionErrorDetectionForSudoPromptFailures() {
        let service = BrewService()
        XCTAssertTrue(
            service.isPermissionError("sudo: a terminal is required to read the password"),
            "Should detect non-TTY sudo prompt failures as permission errors"
        )
    }

    func testAppUpdateCheckIntervalIsSixHours() {
        XCTAssertEqual(MenuBarViewModel.appUpdateCheckInterval, 21_600)
    }

    func testParseUpgradeOutputCapturesFormulaVersionTransitions() {
        let output = """
        ==> Upgrading node 20.1.0 -> 22.0.0
        ==> Summary
        🍺  /opt/homebrew/Cellar/node/22.0.0: 2,000 files, 80MB
        """

        let packages = BrewService.parseUpgradeOutput(output)

        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages.first?.name, "node")
        XCTAssertEqual(packages.first?.oldVersion, "20.1.0")
        XCTAssertEqual(packages.first?.newVersion, "22.0.0")
    }

    func testParseUpgradeOutputCapturesGreedyCaskUpgradeWithoutVersions() {
        let output = """
        ==> Upgrading google-chrome
        ==> Downloading https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg
        """

        let packages = BrewService.parseUpgradeOutput(output)

        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages.first?.name, "google-chrome")
        XCTAssertEqual(packages.first?.oldVersion, "?")
        XCTAssertEqual(packages.first?.newVersion, "?")
    }

    func testParseUpgradeOutputCapturesGreedyCaskSummaryVersions() {
        let output = """
        ==> Upgrading 2 outdated packages:
        google-chrome 136.0.0,137.0.0
        visual-studio-code 1.99.0,1.100.0
        ==> Upgrading google-chrome
        ==> Upgrading visual-studio-code
        """

        let packages = BrewService.parseUpgradeOutput(output)

        XCTAssertEqual(packages.count, 2)
        XCTAssertEqual(packages[0].name, "google-chrome")
        XCTAssertEqual(packages[0].oldVersion, "136.0.0")
        XCTAssertEqual(packages[0].newVersion, "137.0.0")
        XCTAssertEqual(packages[1].name, "visual-studio-code")
        XCTAssertEqual(packages[1].oldVersion, "1.99.0")
        XCTAssertEqual(packages[1].newVersion, "1.100.0")
    }

    func testParseUpgradeOutputAvoidsDuplicatePackageEntries() {
        let output = """
        ==> Upgrading 1 outdated package:
        node 20.1.0 -> 22.0.0
        ==> Upgrading node 20.1.0 -> 22.0.0
        """

        let packages = BrewService.parseUpgradeOutput(output)

        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages.first?.name, "node")
    }

    func testGreedyUpdateRunsRegularUpgradeBeforeGreedyUpgrade() {
        XCTAssertEqual(
            BrewService.upgradeArgumentBatches(greedy: true),
            [
                ["upgrade"],
                ["upgrade", "--greedy"]
            ]
        )
    }
}
