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
        let output = "sudo: a terminal is required to read the password"
        if case .permissionDenied = BrewError.classify(output: output) {
            // pass
        } else {
            XCTFail("Should detect non-TTY sudo prompt failures as permission errors")
        }
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

    func testParseUpgradeOutputHandlesColumnAlignedSummary() {
        // Newer Homebrew prints the upgrade summary as a column-aligned table:
        // the name and old-version columns are padded with runs of spaces so
        // the "->" arrows line up. The old single-space split baked the old
        // version + padding into the name (leaving oldVersion empty) and then
        // emitted a duplicate "?"/"?" entry per package because the malformed
        // name defeated the dedup guard.
        let pad = { (text: String, width: Int) in
            text + String(repeating: " ", count: max(1, width - text.count))
        }
        let summary = [
            "==> Upgrading 3 outdated packages:",
            pad("pnpm", 16) + pad("11.8.0", 52) + "-> 11.9.0 (4MB)",
            pad("warp", 16) + pad("0.2026.06.10.09.27.stable_01", 52) + "-> 0.2026.06.17.09.49.stable_01",
            pad("docker-desktop", 16) + pad("4.78.0,229452", 52) + "-> 4.79.0,230596",
            "==> Fetching pnpm",
            "==> Upgrading pnpm",
            "==> Upgrading warp",
            "==> Upgrading docker-desktop"
        ].joined(separator: "\n")

        let packages = BrewService.parseUpgradeOutput(summary)

        XCTAssertEqual(packages.map(\.name), ["pnpm", "warp", "docker-desktop"])
        XCTAssertEqual(packages.count, 3)
        XCTAssertEqual(packages[0].oldVersion, "11.8.0")
        XCTAssertEqual(packages[0].newVersion, "11.9.0 (4MB)")
        XCTAssertEqual(packages[1].oldVersion, "0.2026.06.10.09.27.stable_01")
        XCTAssertEqual(packages[2].oldVersion, "4.78.0,229452")
        XCTAssertEqual(packages[2].newVersion, "4.79.0,230596")
        XCTAssertFalse(packages.contains { $0.name.contains(" ") }, "names must not absorb version/padding")
        XCTAssertFalse(packages.contains { $0.newVersion == "?" }, "no duplicate '?' placeholder entries")
    }

    func testParseUpgradeOutputHandlesReportedTwoFormulaColumnAlignedSummary() {
        // Regression for the reported issue: `uv` + `vim` upgraded but shown as
        // "4 packages" with ?→? duplicates. Brew padded the old-version column
        // wider than both versions, so the old single-space split malformed
        // *both* names (empty oldVersion) and the later "==> Upgrading" lines
        // spawned a ?/? duplicate for each. With whitespace-run splitting both
        // parse clean and dedupe.
        let pad = { (text: String, width: Int) in
            text + String(repeating: " ", count: max(1, width - text.count))
        }
        let summary = [
            "==> Upgrading 2 outdated packages:",
            pad("uv", 5) + pad("0.11.23", 14) + "-> 0.11.24",
            pad("vim", 5) + pad("9.2.0650", 14) + "-> 9.2.0700",
            "==> Upgrading uv",
            "==> Upgrading vim"
        ].joined(separator: "\n")

        let packages = BrewService.parseUpgradeOutput(summary)

        XCTAssertEqual(packages.map(\.name), ["uv", "vim"])
        XCTAssertEqual(packages.count, 2, "two real upgrades must not be reported as four")
        XCTAssertEqual(packages[0].oldVersion, "0.11.23")
        XCTAssertEqual(packages[0].newVersion, "0.11.24")
        XCTAssertEqual(packages[1].oldVersion, "9.2.0650")
        XCTAssertEqual(packages[1].newVersion, "9.2.0700")
        XCTAssertFalse(packages.contains { $0.newVersion == "?" }, "no '?' duplicate entries")
    }

    func testCasksNeedingReinstallExtractsRefusedCaskNames() {
        // Homebrew refuses to upgrade some auto_updates casks in place and
        // recommends a forced reinstall instead.
        let output = """
        ==> Upgrading lame
        Warning: The cask 'google-chrome' cannot be upgraded as-is. To fix this, run:
        brew reinstall --cask --force google-chrome
        Warning: The cask 'duckduckgo' cannot be upgraded as-is. To fix this, run:
        brew reinstall --cask --force duckduckgo
        """

        XCTAssertEqual(BrewService.casksNeedingReinstall(from: output), ["google-chrome", "duckduckgo"])
    }

    func testCasksNeedingReinstallIgnoresNormalUpgradeOutput() {
        let output = """
        ==> Upgrading 1 outdated package:
        lame 3.100 -> 3.101
        🍺  /opt/homebrew/Cellar/lame/3.101: 27 files, 3.2MB
        """

        XCTAssertTrue(BrewService.casksNeedingReinstall(from: output).isEmpty)
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

    func testSanitizedRepairsMalformedAndDuplicatePackages() {
        // Mirrors a record persisted by the pre-fix parser: real packages whose
        // names absorbed the old version + padding (with an empty oldVersion),
        // each shadowed by a duplicate "?"/"?" entry under the clean name.
        let raw = UpdateResult(
            packages: [
                UpgradedPackage(name: "pnpm       11.8.0                  ", oldVersion: "", newVersion: "11.9.0 (4MB)"),
                UpgradedPackage(name: "warp    ", oldVersion: "0.2026.06.10.09.27.stable_01", newVersion: "0.2026.06.17.09.49.stable_01"),
                UpgradedPackage(name: "docker-desktop  4.78.0,229452            ", oldVersion: "", newVersion: "4.79.0,230596"),
                UpgradedPackage(name: "pnpm", oldVersion: "?", newVersion: "?"),
                UpgradedPackage(name: "warp", oldVersion: "?", newVersion: "?"),
                UpgradedPackage(name: "docker-desktop", oldVersion: "?", newVersion: "?")
            ],
            timestamp: Date()
        )

        let clean = raw.sanitized()

        XCTAssertEqual(clean.packages.map(\.name), ["pnpm", "warp", "docker-desktop"])
        XCTAssertEqual(clean.count, 3)
        XCTAssertEqual(clean.packages[0].oldVersion, "11.8.0", "should recover old version leaked into the name")
        XCTAssertEqual(clean.packages[0].newVersion, "11.9.0 (4MB)")
        XCTAssertEqual(clean.packages[1].oldVersion, "0.2026.06.10.09.27.stable_01")
        XCTAssertEqual(clean.packages[2].oldVersion, "4.78.0,229452")
        XCTAssertFalse(clean.packages.contains { $0.newVersion == "?" }, "duplicate '?' entries should be collapsed")
        XCTAssertFalse(clean.packages.contains { $0.name.contains(" ") }, "names should be trimmed clean")
    }

    func testSanitizedLeavesCleanHistoryUnchanged() {
        // Clean records — including a genuine unknown-version entry that has no
        // duplicate — must pass through untouched (sanitizing is idempotent).
        let result = UpdateResult(
            packages: [
                UpgradedPackage(name: "docker-desktop", oldVersion: "4.78.0,229452", newVersion: "4.79.0,230596"),
                UpgradedPackage(name: "gh", oldVersion: "2.94.0", newVersion: "2.95.0"),
                UpgradedPackage(name: "sdl2-compat", oldVersion: "?", newVersion: "?")
            ],
            timestamp: Date()
        )

        let sanitized = result.sanitized()

        XCTAssertEqual(sanitized.packages.map(\.name), ["docker-desktop", "gh", "sdl2-compat"])
        XCTAssertEqual(sanitized.packages.map(\.oldVersion), ["4.78.0,229452", "2.94.0", "?"])
        XCTAssertEqual(sanitized.packages.map(\.newVersion), ["4.79.0,230596", "2.95.0", "?"])
    }

    func testSanitizedCollapsesReportedUvVimHistoryRecord() {
        // Regression for the reported issue, modelled on the exact History view
        // shown in the report: uv's old version leaked into its name (empty
        // oldVersion), vim parsed clean, and each has a shadow "?"/"?" entry.
        // After loading, the record must collapse back to the two real updates.
        let raw = UpdateResult(
            packages: [
                UpgradedPackage(name: "uv  0.11.23", oldVersion: "", newVersion: "0.11.24"),
                UpgradedPackage(name: "vim", oldVersion: "9.2.0650", newVersion: "9.2.0700"),
                UpgradedPackage(name: "uv", oldVersion: "?", newVersion: "?"),
                UpgradedPackage(name: "vim", oldVersion: "?", newVersion: "?")
            ],
            timestamp: Date()
        )

        let clean = raw.sanitized()

        XCTAssertEqual(clean.count, 2, "the two real packages must not be reported as four")
        XCTAssertEqual(clean.packages.map(\.name), ["uv", "vim"])
        XCTAssertEqual(clean.packages[0].oldVersion, "0.11.23", "uv's leaked old version should be recovered")
        XCTAssertEqual(clean.packages[0].newVersion, "0.11.24")
        XCTAssertEqual(clean.packages[1].oldVersion, "9.2.0650")
        XCTAssertEqual(clean.packages[1].newVersion, "9.2.0700")
        XCTAssertFalse(clean.packages.contains { $0.newVersion == "?" }, "shadow '?' rows should be gone")
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

    func testCleanupArgumentsKeepStandardCleanupAsDefault() {
        XCTAssertEqual(BrewService.cleanupArguments(deepPruneAll: false), ["cleanup"])
        XCTAssertEqual(BrewService.cleanupArguments(deepPruneAll: true), ["cleanup", "--prune=all"])
    }

    func testAutoCleanupStyleDefaultsToStandardCleanup() {
        let suiteName = "topoff-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AutoCleanupStyle.stored(in: defaults), .standard)
        XCTAssertFalse(AutoCleanupStyle.stored(in: defaults).deepPruneAll)
    }

    func testAutoCleanupStyleCanPersistDeepPruneAll() {
        let suiteName = "topoff-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AutoCleanupStyle.deepPruneAll.save(in: defaults)

        XCTAssertEqual(AutoCleanupStyle.stored(in: defaults), .deepPruneAll)
        XCTAssertTrue(AutoCleanupStyle.stored(in: defaults).deepPruneAll)
    }
}
