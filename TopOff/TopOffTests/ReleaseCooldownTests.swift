import XCTest
@testable import TopOff

@MainActor
final class ReleaseCooldownTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSinceReferenceDate: 813_000_000)

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TopOff.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func cask(_ name: String, _ latestVersion: String) -> OutdatedPackage {
        OutdatedPackage(name: name, currentVersion: "1.0", latestVersion: latestVersion, kind: .cask)
    }

    private func formula(_ name: String, _ latestVersion: String) -> OutdatedPackage {
        OutdatedPackage(name: name, currentVersion: "1.0", latestVersion: latestVersion, kind: .formula)
    }

    private func firstSeen(_ packages: [OutdatedPackage], at date: Date) -> [String: FirstSeenVersion] {
        ReleaseCooldown.firstSeenVersions(after: packages, previous: [:], greedyCheck: false, now: date)
    }

    private func daysRemaining(
        _ package: OutdatedPackage,
        cooldownDays: Int = 10,
        scope: ReleaseCooldown.Scope = .casksOnly,
        firstSeen: [String: FirstSeenVersion],
        now: Date
    ) -> Int? {
        ReleaseCooldown.daysRemaining(
            for: package,
            cooldownDays: cooldownDays,
            scope: scope,
            firstSeen: firstSeen,
            now: now
        )
    }

    private func makeViewModel(now: @escaping () -> Date) -> MenuBarViewModel {
        MenuBarViewModel(skipInitialChecks: true, defaults: defaults, now: now)
    }

    // MARK: - Age logic

    func testOffNeverHoldsAVersionBack() {
        let firefox = cask("firefox", "131.0")
        let seen = firstSeen([firefox], at: start)

        XCTAssertNil(daysRemaining(firefox, cooldownDays: 0, scope: .allPackages, firstSeen: seen, now: start))
    }

    func testNewVersionWaitsTheWholeCooldown() {
        let firefox = cask("firefox", "131.0")
        let seen = firstSeen([firefox], at: start)

        XCTAssertEqual(daysRemaining(firefox, firstSeen: seen, now: start), 10)
    }

    func testVersionIsOfferedOnceItHasBeenPendingForTheWholeCooldown() {
        let firefox = cask("firefox", "131.0")
        let seen = firstSeen([firefox], at: start)

        XCTAssertEqual(daysRemaining(firefox, firstSeen: seen, now: start.addingTimeInterval(10 * day - 1)), 1)
        XCTAssertNil(daysRemaining(firefox, firstSeen: seen, now: start.addingTimeInterval(10 * day)))
    }

    func testDaysRemainingRoundsPartDaysUp() {
        let firefox = cask("firefox", "131.0")
        let seen = firstSeen([firefox], at: start)

        XCTAssertEqual(daysRemaining(firefox, firstSeen: seen, now: start.addingTimeInterval(6.5 * day)), 4)
    }

    func testLaterCheckKeepsTheDateTheVersionWasFirstSeen() {
        let firefox = cask("firefox", "131.0")
        let seen = firstSeen([firefox], at: start)

        let rechecked = ReleaseCooldown.firstSeenVersions(
            after: [firefox],
            previous: seen,
            greedyCheck: false,
            now: start.addingTimeInterval(3 * day)
        )

        XCTAssertEqual(rechecked["firefox"], FirstSeenVersion(version: "131.0", date: start))
    }

    func testNewerVersionWhileInCooldownStartsTheCooldownAgain() {
        let seen = firstSeen([cask("firefox", "131.0")], at: start)
        let fourDaysLater = start.addingTimeInterval(4 * day)
        let newer = cask("firefox", "131.0.1")

        let rechecked = ReleaseCooldown.firstSeenVersions(
            after: [newer],
            previous: seen,
            greedyCheck: false,
            now: fourDaysLater
        )

        XCTAssertEqual(rechecked["firefox"], FirstSeenVersion(version: "131.0.1", date: fourDaysLater))
        XCTAssertEqual(daysRemaining(newer, firstSeen: rechecked, now: fourDaysLater), 10)
    }

    func testRegularCheckKeepsPackagesItDidNotList() {
        // Casks that update themselves only show up in a greedy check, so a
        // regular check that leaves them out must not forget when they were seen.
        let seen = firstSeen([cask("firefox", "131.0"), cask("google-chrome", "148.0")], at: start)

        let rechecked = ReleaseCooldown.firstSeenVersions(
            after: [cask("firefox", "131.0")],
            previous: seen,
            greedyCheck: false,
            now: start.addingTimeInterval(day)
        )

        XCTAssertEqual(rechecked["google-chrome"], FirstSeenVersion(version: "148.0", date: start))
    }

    func testGreedyCheckForgetsPackagesNoLongerOutdated() {
        let seen = firstSeen([cask("firefox", "131.0"), cask("google-chrome", "148.0")], at: start)

        let rechecked = ReleaseCooldown.firstSeenVersions(
            after: [cask("firefox", "131.0")],
            previous: seen,
            greedyCheck: true,
            now: start.addingTimeInterval(day)
        )

        XCTAssertEqual(Array(rechecked.keys), ["firefox"])
    }

    func testVersionWithNoRecordCountsAsFirstSeenNow() {
        XCTAssertEqual(daysRemaining(cask("firefox", "131.0"), cooldownDays: 7, firstSeen: [:], now: start), 7)
    }

    func testFirstSeenDateAheadOfTheClockNeverStretchesTheWait() {
        // The clock was set back after the version was first seen.
        let firefox = cask("firefox", "131.0")
        let seen = firstSeen([firefox], at: start.addingTimeInterval(30 * day))

        XCTAssertEqual(daysRemaining(firefox, firstSeen: seen, now: start), 10)
    }

    // MARK: - Which packages it applies to

    func testCasksOnlyLetsFormulaeThroughAtOnce() {
        let node = formula("node", "22.0.0")
        let seen = firstSeen([node], at: start)

        XCTAssertNil(daysRemaining(node, scope: .casksOnly, firstSeen: seen, now: start))
    }

    func testAllPackagesHoldsBackFormulaeToo() {
        let node = formula("node", "22.0.0")
        let seen = firstSeen([node], at: start)

        XCTAssertEqual(daysRemaining(node, scope: .allPackages, firstSeen: seen, now: start), 10)
    }

    func testPackageOfUnknownKindWaitsLikeACask() {
        // When the kind can't be told the cooldown fails closed: a cask let
        // through early would defeat it, a formula held back only waits.
        let unknown = OutdatedPackage(name: "mystery", currentVersion: "1.0", latestVersion: "2.0")
        let seen = firstSeen([unknown], at: start)

        XCTAssertNil(unknown.kind)
        XCTAssertEqual(daysRemaining(unknown, scope: .casksOnly, firstSeen: seen, now: start), 10)
    }

    // MARK: - MenuBarViewModel

    func testCooldownIsOffByDefaultSoEveryPackageIsReady() {
        let vm = makeViewModel(now: { [start] in start })
        vm.applyOutdatedCheck([formula("node", "22.0.0"), cask("firefox", "131.0")], greedy: false)

        XCTAssertEqual(vm.releaseCooldownDays, 0)
        XCTAssertEqual(vm.readyOutdatedPackages.map(\.name), ["node", "firefox"])
        XCTAssertTrue(vm.cooldownOutdatedPackages.isEmpty)
    }

    func testCasksOnlyIsTheDefaultAndLeavesFormulaeInUpdateAll() {
        let vm = makeViewModel(now: { [start] in start })
        vm.applyOutdatedCheck([formula("node", "22.0.0"), cask("firefox", "131.0")], greedy: false)

        vm.releaseCooldownDays = 10

        XCTAssertEqual(vm.releaseCooldownScope, .casksOnly)
        XCTAssertEqual(vm.readyOutdatedPackages.map(\.name), ["node"])
        XCTAssertEqual(vm.cooldownOutdatedPackages.map(\.name), ["firefox"])
        XCTAssertEqual(vm.iconState, .updatesAvailable)

        vm.releaseCooldownScope = .allPackages

        XCTAssertTrue(vm.readyOutdatedPackages.isEmpty)
        XCTAssertEqual(vm.cooldownOutdatedPackages.map(\.name), ["node", "firefox"])
        XCTAssertEqual(vm.iconState, .upToDate)
    }

    func testFormulaDatesAreKeptSoAllPackagesDoesNotStartThemFromZero() {
        var now = start
        let vm = makeViewModel(now: { now })
        vm.releaseCooldownDays = 10
        vm.applyOutdatedCheck([formula("node", "22.0.0")], greedy: false)

        now = start.addingTimeInterval(4 * day)
        vm.applyOutdatedCheck([formula("node", "22.0.0")], greedy: false)
        XCTAssertEqual(vm.readyOutdatedPackages.map(\.name), ["node"])

        vm.releaseCooldownScope = .allPackages

        XCTAssertEqual(
            vm.cooldownDaysRemaining(for: vm.outdatedPackages[0]),
            6,
            "counts from the first check, not from the switch"
        )
    }

    func testCooldownPackageIsListedButLeftOutOfUpdateAllAndTheIcon() {
        let vm = makeViewModel(now: { [start] in start })
        vm.applyOutdatedCheck([cask("firefox", "131.0")], greedy: false)

        vm.releaseCooldownDays = 10

        XCTAssertEqual(vm.cooldownOutdatedPackages.map(\.name), ["firefox"])
        XCTAssertTrue(vm.readyOutdatedPackages.isEmpty, "Update All upgrades only ready packages")
        XCTAssertEqual(vm.iconState, .upToDate)

        vm.releaseCooldownDays = 0

        XCTAssertEqual(vm.readyOutdatedPackages.map(\.name), ["firefox"])
        XCTAssertEqual(vm.iconState, .updatesAvailable, "turning the cooldown off offers the update at once")
    }

    func testOnlyReadyPackagesReachBrewInTheNormalAndAdminBatches() {
        var now = start
        let vm = makeViewModel(now: { now })
        vm.releaseCooldownDays = 10
        vm.releaseCooldownScope = .allPackages
        vm.applyOutdatedCheck([cask("firefox", "131.0"), formula("node", "22.0")], greedy: false)

        // Both have outlasted the cooldown by the next check; a new cask has not
        now = start.addingTimeInterval(11 * day)
        vm.applyOutdatedCheck(
            [cask("firefox", "131.0"), formula("node", "22.0"), cask("google-chrome", "148.0")],
            greedy: false
        )
        let ready = MenuBarViewModel.uniquePackages(vm.readyOutdatedPackages)
        let names = ready.map(\.name)

        XCTAssertEqual(names, ["firefox", "node"])
        XCTAssertEqual(
            BrewService.upgradeArgumentBatches(greedy: true, packageNames: names),
            [["upgrade", "firefox", "node"], ["upgrade", "--greedy", "firefox", "node"]]
        )
        XCTAssertEqual(
            BrewService.adminUpgradeArgumentBatches(caskNames: ready.filter { $0.kind == .cask }.map(\.name)),
            [["upgrade", "--cask", "--greedy", "firefox"]]
        )
    }

    func testCooldownPackageBecomesReadyOnceItsCooldownPasses() {
        var now = start
        let vm = makeViewModel(now: { now })
        vm.releaseCooldownDays = 3
        vm.applyOutdatedCheck([cask("firefox", "131.0")], greedy: false)
        XCTAssertEqual(vm.cooldownDaysRemaining(for: vm.outdatedPackages[0]), 3)

        now = start.addingTimeInterval(3 * day)
        vm.applyOutdatedCheck([cask("firefox", "131.0")], greedy: false)

        XCTAssertEqual(vm.readyOutdatedPackages.map(\.name), ["firefox"])
        XCTAssertTrue(vm.cooldownOutdatedPackages.isEmpty)
    }

    func testUpdateAllInEitherPlaceLeavesOutPackagesInCooldown() {
        // Update All in the menu and in the Outdated Packages window both call
        // updateAll, which upgrades updateCandidatePackages() and nothing else.
        var now = start
        let vm = makeViewModel(now: { now })
        vm.releaseCooldownDays = 7
        vm.applyOutdatedCheck([cask("firefox", "131.0")], greedy: false)
        now = start.addingTimeInterval(8 * day)
        vm.applyOutdatedCheck([cask("firefox", "131.0"), cask("google-chrome", "148.0")], greedy: false)

        XCTAssertEqual(vm.updateCandidatePackages().map(\.name), ["firefox"])
        XCTAssertEqual(vm.cooldownOutdatedPackages.map(\.name), ["google-chrome"])

        // With only packages in cooldown, Update All has nothing to run and
        // the window's button is disabled (it checks readyOutdatedPackages)
        vm.releaseCooldownDays = 14
        XCTAssertTrue(vm.updateCandidatePackages().isEmpty)
        XCTAssertTrue(vm.readyOutdatedPackages.isEmpty)
    }

    func testDaysLeftAreSaidInWholeDaysWithTheSingularForOne() {
        XCTAssertEqual(ReleaseCooldown.dayCount(1), "1 day")
        XCTAssertEqual(ReleaseCooldown.dayCount(3), "3 days")

        // What each place shows for a package three days from ready
        let vm = makeViewModel(now: { [start] in start })
        vm.releaseCooldownDays = 3
        vm.applyOutdatedCheck([cask("firefox", "131.0")], greedy: false)
        let daysLeft = vm.cooldownDaysRemaining(for: vm.outdatedPackages[0])

        XCTAssertEqual(daysLeft.map { "Available in \(ReleaseCooldown.dayCount($0))" }, "Available in 3 days")
    }

    func testSkippedPackageIsHiddenRatherThanListedAsCooldown() {
        let vm = makeViewModel(now: { [start] in start })
        vm.releaseCooldownDays = 10
        vm.applyOutdatedCheck([cask("firefox", "131.0"), cask("google-chrome", "148.0")], greedy: false)

        vm.skipPackage(vm.outdatedPackages[0])

        XCTAssertEqual(vm.cooldownOutdatedPackages.map(\.name), ["google-chrome"])
        XCTAssertTrue(vm.readyOutdatedPackages.isEmpty)
    }

    func testSettingAndFirstSeenDatesSurviveARelaunch() {
        let vm = makeViewModel(now: { [start] in start })
        vm.releaseCooldownDays = 10
        vm.applyOutdatedCheck([cask("firefox", "131.0")], greedy: false)

        let threeDaysLater = start.addingTimeInterval(3 * day)
        let relaunched = makeViewModel(now: { threeDaysLater })
        relaunched.outdatedPackages = [cask("firefox", "131.0")]

        XCTAssertEqual(relaunched.releaseCooldownDays, 10)
        XCTAssertEqual(relaunched.cooldownDaysRemaining(for: relaunched.outdatedPackages[0]), 7)
    }

    func testScopeSurvivesARelaunch() {
        let vm = makeViewModel(now: { [start] in start })
        vm.releaseCooldownScope = .allPackages

        let relaunched = makeViewModel(now: { [start] in start })

        XCTAssertEqual(relaunched.releaseCooldownScope, .allPackages)
        XCTAssertEqual(defaults.string(forKey: "releaseCooldownScope"), "allPackages")
    }

    // MARK: - Compatibility

    func testSettingsSavedByTopOff22KeepTheCooldownOffAndNothingWaiting() throws {
        // Exactly the keys TopOff 2.2 saves, none of the release cooldown's
        defaults.set(43_200.0, forKey: "checkInterval")
        defaults.set(false, forKey: "launchAtLogin")
        defaults.set(false, forKey: "autoCleanupEnabled")
        defaults.set("deepPruneAll", forKey: "autoCleanupStyle")
        defaults.set(true, forKey: "greedyModeEnabled")
        defaults.set(true, forKey: "rememberSkippedPackages")
        defaults.set(false, forKey: "notificationsEnabled")
        defaults.set(try JSONEncoder().encode(["warp"]), forKey: "rememberedSkipList")
        let history = [UpdateResult(
            packages: [UpgradedPackage(name: "gh", oldVersion: "2.94.0", newVersion: "2.95.0")],
            timestamp: start
        )]
        defaults.set(try JSONEncoder().encode(history), forKey: "updateHistory")

        let vm = MenuBarViewModel(
            skipInitialChecks: true,
            defaults: defaults,
            loginItemManager: SpyLaunchAtLoginManager(),
            now: { [start] in start }
        )

        // Loading writes none of the new keys, and 2.2's settings load as saved
        for key in ["releaseCooldownDays", "releaseCooldownScope", "firstSeenVersions"] {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertEqual(vm.checkInterval, 43_200)
        XCTAssertFalse(vm.autoCleanupEnabled)
        XCTAssertEqual(vm.autoCleanupStyle, .deepPruneAll)
        XCTAssertTrue(vm.greedyModeEnabled)
        XCTAssertTrue(vm.rememberSkippedPackages)
        XCTAssertFalse(vm.notificationsEnabled)
        XCTAssertEqual(vm.rememberedSkipList, ["warp"])
        XCTAssertEqual(vm.updateHistory.first?.packages.map(\.name), ["gh"])

        // The cooldown is off, so every visible package is offered, as in 2.2
        vm.applyOutdatedCheck([
            formula("node", "22.0.0"),
            cask("firefox", "131.0"),
            cask("google-chrome", "148.0"),
            cask("warp", "0.2026"),
            OutdatedPackage(name: "mystery", currentVersion: "1.0", latestVersion: "2.0")
        ], greedy: true)
        vm.skipPackage(vm.outdatedPackages[2])

        XCTAssertEqual(vm.releaseCooldownDays, 0)
        XCTAssertTrue(vm.cooldownOutdatedPackages.isEmpty)
        XCTAssertEqual(vm.readyOutdatedPackages.map(\.name), ["node", "firefox", "mystery"])
        XCTAssertEqual(vm.readyOutdatedPackages.map(\.name), vm.visibleOutdatedPackages.map(\.name))
        XCTAssertEqual(vm.iconState, .updatesAvailable)
    }

    func testScopeSavedByALaterVersionFallsBackToCasksOnly() {
        defaults.set("casksAndTaps", forKey: "releaseCooldownScope")

        XCTAssertEqual(makeViewModel(now: { [start] in start }).releaseCooldownScope, .casksOnly)
    }

    func testDayCountThisVersionDoesNotOfferFallsBackToOff() {
        for saved in [30, -1, Int.max] {
            defaults.set(saved, forKey: "releaseCooldownDays")

            let vm = makeViewModel(now: { [start] in start })
            vm.applyOutdatedCheck([cask("firefox", "131.0")], greedy: false)

            XCTAssertEqual(vm.releaseCooldownDays, 0, "saved \(saved)")
            XCTAssertEqual(vm.readyOutdatedPackages.map(\.name), ["firefox"], "saved \(saved)")
        }
    }

    func testCorruptFirstSeenRecordFallsBackToNoDates() throws {
        let corruptRecords: [Any] = [Data("not json".utf8), "not data", 42]
        for corrupt in corruptRecords {
            defaults.set(corrupt, forKey: "firstSeenVersions")
            defaults.set(10, forKey: "releaseCooldownDays")

            let vm = makeViewModel(now: { [start] in start })
            XCTAssertTrue(vm.firstSeenVersions.isEmpty)

            // The next check dates what it lists from then, and saves a good record
            vm.applyOutdatedCheck([cask("firefox", "131.0")], greedy: false)
            XCTAssertEqual(vm.cooldownDaysRemaining(for: vm.outdatedPackages[0]), 10)
            let saved = try XCTUnwrap(defaults.data(forKey: "firstSeenVersions"))
            let record = try JSONDecoder().decode([String: FirstSeenVersion].self, from: saved)
            XCTAssertEqual(record["firefox"], FirstSeenVersion(version: "131.0", date: start))
        }
    }
}
