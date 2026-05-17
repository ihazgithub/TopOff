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

    func testUpgradingPackageNameIgnoresSummaryLines() {
        XCTAssertNil(BrewService.upgradingPackageName(from: "==> Upgrading 3 outdated packages:"))
        XCTAssertEqual(
            BrewService.upgradingPackageName(from: "==> Upgrading pnpm 11.1.1 -> 11.1.2"),
            "pnpm"
        )
        XCTAssertEqual(
            BrewService.upgradingPackageName(from: "==> Upgrading reaper"),
            "reaper"
        )
    }

    func testUpdateResultSupplementedWithObservedProgressItems() {
        let parsed = UpdateResult(
            packages: [
                UpgradedPackage(name: "pnpm", oldVersion: "11.1.1", newVersion: "11.1.2")
            ],
            timestamp: Date()
        )
        let progressItems = [
            UpdateProgressItem(name: "pnpm", currentVersion: "11.1.1", latestVersion: "11.1.2", state: .finished),
            UpdateProgressItem(name: "reaper", currentVersion: "7.72", latestVersion: "7.73", state: .finished),
            UpdateProgressItem(name: "queued-only", currentVersion: "1.0", latestVersion: "2.0", state: .queued)
        ]

        let supplemented = parsed.supplemented(with: progressItems)

        XCTAssertEqual(supplemented.packages.map(\.name), ["pnpm", "reaper"])
        XCTAssertEqual(supplemented.packages[1].oldVersion, "7.72")
        XCTAssertEqual(supplemented.packages[1].newVersion, "7.73")
    }

    func testUpdateResultDoesNotSupplementAttemptedProgressItems() {
        let parsed = UpdateResult(packages: [], timestamp: Date())
        let progressItems = [
            UpdateProgressItem(name: "duckduckgo", currentVersion: "1.188.0,697", latestVersion: "1.189.0,703", state: .attempted),
            UpdateProgressItem(name: "google-chrome", currentVersion: "146.0.7680.80", latestVersion: "148.0.7778.168", state: .repairing)
        ]

        let supplemented = parsed.supplemented(with: progressItems)

        XCTAssertTrue(supplemented.isEmpty)
    }

    func testParseOutdatedVerboseCapturesGreedyCaskNotEqualLines() {
        let output = """
        duckduckgo (1.188.0,697.upgrading) != 1.189.0,703
        google-chrome (146.0.7680.80.upgrading) != 148.0.7778.168
        node (20.1.0) < 22.0.0
        """

        let packages = BrewService.parseOutdatedVerbose(output)

        XCTAssertEqual(packages.count, 3)
        XCTAssertEqual(packages[0].name, "duckduckgo")
        XCTAssertEqual(packages[0].currentVersion, "1.188.0,697.upgrading")
        XCTAssertEqual(packages[0].latestVersion, "1.189.0,703")
        XCTAssertEqual(packages[1].name, "google-chrome")
        XCTAssertEqual(packages[1].currentVersion, "146.0.7680.80.upgrading")
        XCTAssertEqual(packages[1].latestVersion, "148.0.7778.168")
        XCTAssertEqual(packages[2].name, "node")
        XCTAssertEqual(packages[2].currentVersion, "20.1.0")
        XCTAssertEqual(packages[2].latestVersion, "22.0.0")
    }

    func testOutdatedPackageMarksInterruptedCaskUpgradeAsRepairable() {
        let package = OutdatedPackage(
            name: "duckduckgo",
            currentVersion: "1.188.0,697.upgrading",
            latestVersion: "1.189.0,703"
        )
        let normalPackage = OutdatedPackage(
            name: "pnpm",
            currentVersion: "11.1.1",
            latestVersion: "11.1.2"
        )

        XCTAssertTrue(package.hasInterruptedCaskUpgrade)
        XCTAssertFalse(normalPackage.hasInterruptedCaskUpgrade)
    }

    func testRepairingPackageNameCapturesRepairProgressLines() {
        XCTAssertEqual(
            BrewService.repairingPackageName(from: "==> Repairing google-chrome"),
            "google-chrome"
        )
        XCTAssertNil(BrewService.repairingPackageName(from: "==> Installing Cask google-chrome"))
    }

    func testStaleCaskUpgradeBackupPathsFindsVersionAndMetadataBackups() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("topoff-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let caskroom = root.appendingPathComponent("Caskroom/google-chrome")
        try FileManager.default.createDirectory(
            at: caskroom.appendingPathComponent("146.0.7680.80.upgrading"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: caskroom.appendingPathComponent("146.0.7680.80"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: caskroom.appendingPathComponent(".metadata/146.0.7680.80.upgrading"),
            withIntermediateDirectories: true
        )

        let paths = try BrewService.staleCaskUpgradeBackupPaths(
            packageName: "google-chrome",
            homebrewPrefix: root.path
        ).map(\.lastPathComponent).sorted()

        XCTAssertEqual(paths, ["146.0.7680.80.upgrading", "146.0.7680.80.upgrading"])
    }

    func testMoveStaleCaskUpgradeBackupsMovesOnlyUpgradingDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("topoff-tests-\(UUID().uuidString)")
        let recoveryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("topoff-recovery-tests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: recoveryRoot)
        }

        let caskroom = root.appendingPathComponent("Caskroom/duckduckgo")
        let staleVersion = caskroom.appendingPathComponent("1.188.0,697.upgrading")
        let currentVersion = caskroom.appendingPathComponent("1.188.0,697")
        let staleMetadata = caskroom.appendingPathComponent(".metadata/1.188.0,697.upgrading")
        try FileManager.default.createDirectory(at: staleVersion, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentVersion, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleMetadata, withIntermediateDirectories: true)

        let moved = try BrewService.moveStaleCaskUpgradeBackups(
            packageName: "duckduckgo",
            homebrewPrefix: root.path,
            recoveryRoot: recoveryRoot
        )

        XCTAssertEqual(moved.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleVersion.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleMetadata.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentVersion.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: recoveryRoot.path).count,
            1
        )
    }

    func testUpdateResultExcludesPackagesStillOutdatedAfterUpgrade() {
        let result = UpdateResult(
            packages: [
                UpgradedPackage(name: "duckduckgo", oldVersion: "1.188.0,697", newVersion: "1.189.0,703"),
                UpgradedPackage(name: "pnpm", oldVersion: "11.1.1", newVersion: "11.1.2")
            ],
            timestamp: Date()
        )
        let stillOutdated = [
            OutdatedPackage(name: "duckduckgo", currentVersion: "1.188.0,697.upgrading", latestVersion: "1.189.0,703")
        ]

        let filtered = result.excludingPackagesStillOutdated(stillOutdated)

        XCTAssertEqual(filtered.packages.map(\.name), ["pnpm"])
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

    func testGreedyUpdateCanTargetSpecificPackages() {
        XCTAssertEqual(
            BrewService.upgradeArgumentBatches(greedy: true, packageNames: ["pnpm", "reaper"]),
            [
                ["upgrade", "pnpm", "reaper"],
                ["upgrade", "--greedy", "pnpm", "reaper"]
            ]
        )
    }
}
