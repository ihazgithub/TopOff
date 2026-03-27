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
        ==> Upgrading 1 outdated package:
        google-chrome 136.0.0,137.0.0
        ==> Upgrading google-chrome
        ==> Downloading https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg
        """

        let packages = BrewService.parseUpgradeOutput(output)

        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages.first?.name, "google-chrome")
        XCTAssertEqual(packages.first?.oldVersion, "?")
        XCTAssertEqual(packages.first?.newVersion, "?")
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
}
