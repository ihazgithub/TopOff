import SwiftUI
import ServiceManagement
import AppKit

enum MenuBarIconState {
    case upToDate         // Full mug - no updates available
    case updatesAvailable // Half-full mug - packages need updating
    case checking         // Spinner - checking for updates
    case updating         // Spinner - running brew upgrade
    case checkmark        // Brief success indicator

    var isCustomImage: Bool {
        switch self {
        case .upToDate, .updatesAvailable:
            return true
        case .checking, .updating, .checkmark:
            return false
        }
    }

    var imageName: String {
        switch self {
        case .upToDate:
            return "MenuBarFull"
        case .updatesAvailable:
            return "MenuBarIcon"
        case .checking, .updating:
            return "arrow.triangle.2.circlepath"
        case .checkmark:
            return "checkmark.circle.fill"
        }
    }
}

/// Abstraction over the system "launch at login" registration. Injecting this
/// lets `MenuBarViewModel` be unit-tested without mutating the user's real
/// login items through `SMAppService`.
protocol LaunchAtLoginManaging {
    func setEnabled(_ enabled: Bool)
}

/// Production implementation backed by `SMAppService.mainApp`.
struct SMAppServiceLaunchAtLogin: LaunchAtLoginManaging {
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    static let appUpdateCheckInterval: TimeInterval = 21_600

    @Published var iconState: MenuBarIconState = .upToDate {
        didSet {
            if iconState == .checking || iconState == .updating {
                startIconAnimation()
            } else {
                stopIconAnimation()
            }
        }
    }
    @Published var lastUpdateResult: UpdateResult?
    @Published var lastCleanupResult: CleanupResult?
    @Published private(set) var isRunning = false
    @Published var statusMessage: String?
    @Published private(set) var updateProgress: UpdateProgressSnapshot?
    @Published var outdatedPackages: [OutdatedPackage] = []
    @Published var skippedPackages: Set<String> = []
    @Published var checkInterval: TimeInterval {
        didSet {
            defaults.set(checkInterval, forKey: "checkInterval")
            restartPeriodicChecks()
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }
    @Published var autoCleanupEnabled: Bool {
        didSet {
            defaults.set(autoCleanupEnabled, forKey: "autoCleanupEnabled")
        }
    }
    @Published var autoCleanupStyle: AutoCleanupStyle {
        didSet {
            autoCleanupStyle.save(in: defaults)
        }
    }
    @Published var greedyModeEnabled: Bool {
        didSet {
            defaults.set(greedyModeEnabled, forKey: "greedyModeEnabled")
        }
    }
    @Published var rememberSkippedPackages: Bool {
        didSet {
            defaults.set(rememberSkippedPackages, forKey: "rememberSkippedPackages")
        }
    }
    @Published var rememberedSkipList: Set<String> {
        didSet {
            saveRememberedSkipList()
        }
    }

    @Published var appUpdateInfo: AppUpdateInfo?
    @Published var isCheckingForAppUpdate = false
    @Published var appUpdateChecked = false
    @Published var spinnerFrame: NSImage?
    @Published var updateHistory: [UpdateResult] = [] {
        didSet {
            saveUpdateHistory()
        }
    }

    private let defaults: UserDefaults
    private let loginItemManager: LaunchAtLoginManaging
    private let brewService = BrewService()
    private let updateChecker = UpdateChecker()
    private let notificationManager = NotificationManager.shared
    private let networkMonitor = NetworkMonitor()
    private var checkTimer: Timer?
    private var appUpdateCheckTimer: Timer?
    private var iconAnimationTimer: Timer?
    private var spinnerFrames: [NSImage] = []
    private var spinnerFrameIndex = 0
    @Published private var initialCheckSucceeded = false

    init(
        skipInitialChecks: Bool = false,
        defaults: UserDefaults = .standard,
        loginItemManager: LaunchAtLoginManaging = SMAppServiceLaunchAtLogin()
    ) {
        self.defaults = defaults
        self.loginItemManager = loginItemManager
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.checkInterval = defaults.object(forKey: "checkInterval") as? TimeInterval ?? 14400
        // Default to true for auto cleanup — UserDefaults.bool returns false if key doesn't exist
        if defaults.object(forKey: "autoCleanupEnabled") == nil {
            self.autoCleanupEnabled = true
        } else {
            self.autoCleanupEnabled = defaults.bool(forKey: "autoCleanupEnabled")
        }
        self.autoCleanupStyle = AutoCleanupStyle.stored(in: defaults)
        self.greedyModeEnabled = defaults.bool(forKey: "greedyModeEnabled")
        self.rememberSkippedPackages = defaults.bool(forKey: "rememberSkippedPackages")
        self.rememberedSkipList = Self.loadRememberedSkipList(from: defaults)
        spinnerFrames = Self.generateSpinnerFrames()
        loadUpdateHistory()
        defaults.removeObject(forKey: "packagesNeedingAttention")
        notificationManager.requestPermission()

        // Start network monitor to handle connectivity restoration
        startNetworkMonitoring()

        guard !skipInitialChecks else { return }

        // Check for updates on launch
        Task {
            let success = await checkForUpdates()
            initialCheckSucceeded = success
            startPeriodicChecks()
        }

        // Check for app updates from GitHub
        Task {
            appUpdateInfo = await updateChecker.checkForUpdate()
            startPeriodicAppUpdateChecks()
        }
    }

    /// Visible outdated packages (excludes both session skips and remembered skips)
    var visibleOutdatedPackages: [OutdatedPackage] {
        let allSkipped = skippedPackages.union(rememberedSkipList)
        return outdatedPackages.filter { !allSkipped.contains($0.name) }
    }

    /// True when the menu should render the subtle "All packages up to date"
    /// confirmation row — there are no outdated packages and at least one
    /// successful check has completed since launch.
    var showsUpToDateConfirmation: Bool {
        initialCheckSucceeded && visibleOutdatedPackages.isEmpty && !isRunning
    }

    func updateAll(greedy: Bool) {
        guard !isRunning else { return }

        Task {
            isRunning = true
            iconState = .checking
            statusMessage = "Checking for updates..."
            var packagesToUpdate: [OutdatedPackage] = []

            do {
                let shouldCheckGreedy = greedy || greedyModeEnabled
                let refreshedOutdatedPackages = try await brewService.checkOutdated(greedy: shouldCheckGreedy)
                outdatedPackages = refreshedOutdatedPackages

                packagesToUpdate = updateCandidatePackages()
                guard !packagesToUpdate.isEmpty else {
                    statusMessage = "No updates to run"
                    updateIconState()
                    isRunning = false
                    return
                }

                iconState = .updating
                beginUpdateProgress(for: packagesToUpdate)
                statusMessage = updateProgress?.title ?? "Updating packages..."

                let result = try await performUpdates(
                    packagesToUpdate,
                    greedy: greedy,
                    useAdmin: false
                )
                finishUpdateProgress()
                let completedResult = try await finalizeUpdateResult(result, greedy: greedy)

                // Run cleanup if auto cleanup is enabled
                if autoCleanupEnabled {
                    lastCleanupResult = try? await runAutoCleanup()
                }

                let remainingCount = visibleOutdatedPackages.count
                if remainingCount == 0 {
                    statusMessage = nil
                    await showSuccessAnimation()
                } else {
                    statusMessage = "\(remainingCount) item\(remainingCount == 1 ? "" : "s") still need updates"
                    updateIconState()
                }

                var message = completionMessage(for: completedResult, remainingCount: remainingCount)
                if let cleanup = lastCleanupResult, !cleanup.freedSpace.isEmpty {
                    message += ". Freed \(cleanup.freedSpace)"
                }
                notificationManager.showCompletionNotification(success: true, message: message)
                updateProgress = nil
            } catch {
                let errorOutput = extractErrorOutput(from: error)
                let classified = BrewError.classify(output: errorOutput)
                if case .permissionDenied = classified {
                    do {
                        statusMessage = "Retrying with admin privileges..."
                        let result = try await performUpdates(
                            packagesToUpdate,
                            greedy: greedy,
                            useAdmin: true
                        )
                        finishUpdateProgress()
                        let completedResult = try await finalizeUpdateResult(result, greedy: greedy)

                        if autoCleanupEnabled {
                            lastCleanupResult = try? await runAutoCleanup()
                        }

                        let remainingCount = visibleOutdatedPackages.count
                        if remainingCount == 0 {
                            statusMessage = nil
                            await showSuccessAnimation()
                        } else {
                            statusMessage = "\(remainingCount) item\(remainingCount == 1 ? "" : "s") still need updates"
                            updateIconState()
                        }

                        var message = completionMessage(for: completedResult, remainingCount: remainingCount)
                        if let cleanup = lastCleanupResult, !cleanup.freedSpace.isEmpty {
                            message += ". Freed \(cleanup.freedSpace)"
                        }
                        notificationManager.showCompletionNotification(success: true, message: message)
                        updateProgress = nil
                    } catch {
                        statusMessage = nil
                        updateProgress = nil
                        iconState = outdatedPackages.isEmpty ? .upToDate : .updatesAvailable
                        notifyFailure(error)
                    }
                } else {
                    statusMessage = nil
                    updateProgress = nil
                    iconState = outdatedPackages.isEmpty ? .upToDate : .updatesAvailable
                    notifyFailure(error)
                }
            }

            isRunning = false
        }
    }

    func upgradePackage(_ package: OutdatedPackage) {
        guard !isRunning else { return }

        Task {
            isRunning = true
            iconState = .updating
            statusMessage = "Updating \(package.name)..."

            do {
                let result = try await brewService.upgradePackage(package)

                // Remove from outdated list
                outdatedPackages.removeAll { $0.name == package.name }
                skippedPackages.remove(package.name)

                // Merge into last update result
                if let existing = lastUpdateResult {
                    lastUpdateResult = UpdateResult(
                        packages: existing.packages + result.packages,
                        timestamp: Date()
                    )
                } else {
                    lastUpdateResult = result
                }
                addToHistory(result)

                // Run cleanup if auto cleanup is enabled
                if autoCleanupEnabled {
                    lastCleanupResult = try? await runAutoCleanup()
                }

                statusMessage = nil
                updateIconState()

                let message = "\(package.name) upgraded"
                notificationManager.showCompletionNotification(success: true, message: message)
            } catch {
                let errorOutput = extractErrorOutput(from: error)
                let classified = BrewError.classify(output: errorOutput)
                if case .permissionDenied = classified {
                    do {
                        statusMessage = "Retrying \(package.name) with admin privileges..."
                        let result = try await brewService.upgradePackageWithAdmin(package)

                        outdatedPackages.removeAll { $0.name == package.name }
                        skippedPackages.remove(package.name)

                        if let existing = lastUpdateResult {
                            lastUpdateResult = UpdateResult(
                                packages: existing.packages + result.packages,
                                timestamp: Date()
                            )
                        } else {
                            lastUpdateResult = result
                        }
                        addToHistory(result)

                        if autoCleanupEnabled {
                            lastCleanupResult = try? await runAutoCleanup()
                        }

                        statusMessage = nil
                        updateIconState()

                        let message = "\(package.name) upgraded"
                        notificationManager.showCompletionNotification(success: true, message: message)
                    } catch {
                        statusMessage = nil
                        updateIconState()
                        notifyFailure(error)
                    }
                } else {
                    statusMessage = nil
                    updateIconState()
                    notifyFailure(error)
                }
            }

            isRunning = false
        }
    }

    func skipPackage(_ package: OutdatedPackage) {
        if rememberSkippedPackages {
            rememberedSkipList.insert(package.name)
        } else {
            skippedPackages.insert(package.name)
        }
        updateIconState()
    }

    func runCleanup(deepPruneAll: Bool = false) {
        guard !isRunning else { return }

        Task {
            isRunning = true
            statusMessage = deepPruneAll ? "Deep pruning Homebrew cache..." : "Cleaning up..."

            do {
                lastCleanupResult = try await brewService.cleanup(deepPruneAll: deepPruneAll)
                statusMessage = nil

                let message: String
                if let result = lastCleanupResult, !result.freedSpace.isEmpty {
                    message = deepPruneAll ? "Deep prune freed \(result.freedSpace)" : "Freed \(result.freedSpace)"
                } else {
                    message = deepPruneAll ? "No Homebrew cache to prune" : "Nothing to clean up"
                }
                notificationManager.showCompletionNotification(success: true, message: message)
            } catch {
                statusMessage = nil
                notifyFailure(error, fallbackTitle: "Cleanup couldn't complete")
            }

            isRunning = false
        }
    }

    func runDeepCachePrune() {
        guard !isRunning, promptForDeepCachePrune() else { return }
        runCleanup(deepPruneAll: true)
    }

    func setAutoCleanupStyle(_ style: AutoCleanupStyle) {
        guard style != autoCleanupStyle else { return }
        if style == .deepPruneAll && !promptForAutomaticDeepCachePrune() {
            return
        }

        autoCleanupStyle = style
    }

    @discardableResult
    func checkForUpdates() async -> Bool {
        guard !isRunning else { return false }

        isRunning = true
        iconState = .checking
        statusMessage = "Checking for updates..."

        var success = false
        do {
            let refreshedOutdatedPackages = try await brewService.checkOutdated(greedy: greedyModeEnabled)
            outdatedPackages = refreshedOutdatedPackages
            skippedPackages = []
            updateIconState()
            success = true
        } catch {
            iconState = .upToDate
            print("Failed to check for updates: \(error)")
        }

        statusMessage = nil
        isRunning = false
        return success
    }

    func checkForAppUpdate() {
        Task {
            isCheckingForAppUpdate = true
            appUpdateInfo = await updateChecker.checkForUpdate()
            isCheckingForAppUpdate = false
            appUpdateChecked = true
        }
    }

    private func promptForDeepCachePrune() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Run Deep Cache Prune?"
        alert.informativeText = """
        This will run brew cleanup --prune=all and delete all Homebrew cached downloads.

        Installed apps and command line tools stay installed, but Homebrew may need to download files again later.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Run Deep Prune")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func promptForAutomaticDeepCachePrune() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Use Deep Cache Prune Automatically?"
        alert.informativeText = """
        Auto Cleanup will run brew cleanup --prune=all after successful updates.

        This can reclaim more disk space by deleting Homebrew cached downloads. Installed apps and command line tools stay installed, but Homebrew may need to download files again later.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Use Deep Prune")
        alert.addButton(withTitle: "Keep Standard")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func extractErrorOutput(from error: Error) -> String {
        if let brewError = error as? BrewError {
            switch brewError {
            case .commandFailed(let output):
                return output
            case .permissionDenied(let output):
                return output
            case .brewNotFound:
                return ""
            case .networkUnavailable(let output):
                return output
            case .diskFull(let output):
                return output
            case .commandLineToolsRequired(let output):
                return output
            case .brewBusy(let output):
                return output
            case .caskUnavailable(_, let output):
                return output
            }
        }
        return error.localizedDescription
    }

    private func notifyFailure(_ error: Error, fallbackTitle: String = "Update couldn't complete") {
        let friendly = (error as? LocalizedError)
        let title = friendly?.errorDescription ?? fallbackTitle
        let body  = friendly?.recoverySuggestion ?? "Try again, or run brew doctor in Terminal for diagnosis."
        notificationManager.showCompletionNotification(success: false, title: title, body: body)
    }

    private func updateIconState() {
        if visibleOutdatedPackages.isEmpty {
            iconState = .upToDate
        } else {
            iconState = .updatesAvailable
        }
    }

    private func beginUpdateProgress(for packages: [OutdatedPackage]) {
        let items = packages.map {
            UpdateProgressItem(
                name: $0.name,
                currentVersion: $0.currentVersion,
                latestVersion: $0.latestVersion,
                state: .queued
            )
        }
        updateProgress = items.isEmpty ? nil : UpdateProgressSnapshot(items: items)
    }

    private func updateCandidatePackages() -> [OutdatedPackage] {
        Self.uniquePackages(visibleOutdatedPackages)
    }

    private func runAutoCleanup() async throws -> CleanupResult {
        statusMessage = autoCleanupStyle.deepPruneAll ? "Deep pruning Homebrew cache..." : "Cleaning up..."
        return try await brewService.cleanup(deepPruneAll: autoCleanupStyle.deepPruneAll)
    }

    nonisolated static func uniquePackages(_ source: [OutdatedPackage]) -> [OutdatedPackage] {
        var packages: [OutdatedPackage] = []
        var names = Set<String>()

        for package in source where !names.contains(package.name) {
            packages.append(package)
            names.insert(package.name)
        }

        return packages
    }

    private func performUpdates(
        _ packages: [OutdatedPackage],
        greedy: Bool,
        useAdmin: Bool
    ) async throws -> UpdateResult {
        let regularPackages = packages.filter { !$0.hasInterruptedCaskUpgrade }
        let repairPackages = packages.filter(\.hasInterruptedCaskUpgrade)
        var completedPackages: [UpgradedPackage] = []
        var capturedNames = Set<String>()

        func append(_ result: UpdateResult) {
            for package in result.packages where !capturedNames.contains(package.name) {
                capturedNames.insert(package.name)
                completedPackages.append(package)
            }
        }

        let progressHandler: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in
                self?.handleProgressLine(line)
            }
        }

        if !regularPackages.isEmpty {
            let result: UpdateResult
            if useAdmin {
                result = try await brewService.updateAllWithAdmin(
                    greedy: greedy,
                    packages: regularPackages,
                    onProgress: progressHandler
                )
            } else {
                result = try await brewService.updateAll(
                    greedy: greedy,
                    packages: regularPackages,
                    onProgress: progressHandler
                )
            }
            append(result)
        }

        if !repairPackages.isEmpty {
            let result = try await brewService.repairInterruptedCaskUpgrades(
                repairPackages,
                useAdmin: useAdmin,
                onProgress: progressHandler
            )
            append(result)
        }

        return UpdateResult(packages: completedPackages, timestamp: Date())
    }

    private func handleProgressLine(_ line: String) {
        if let name = BrewService.repairingPackageName(from: line) {
            markPackage(named: name, state: .repairing)
        } else if let name = BrewService.upgradingPackageName(from: line) {
            markPackage(named: name, state: .updating)
        }
    }

    private func markPackage(named name: String, state: UpdateProgressItem.State) {
        var items = updateProgress?.items ?? []
        if let currentIndex = items.firstIndex(where: { $0.state == .updating || $0.state == .repairing }) {
            items[currentIndex].state = .attempted
        }

        if let index = items.firstIndex(where: { $0.name == name }) {
            items[index].state = state
        } else {
            items.append(UpdateProgressItem(
                name: name,
                currentVersion: "?",
                latestVersion: "?",
                state: state
            ))
        }

        updateProgress = UpdateProgressSnapshot(items: items)
        statusMessage = updateProgress?.title
    }

    private func finishUpdateProgress() {
        guard var items = updateProgress?.items else { return }

        for index in items.indices where items[index].state == .updating || items[index].state == .repairing {
            items[index].state = .attempted
        }

        updateProgress = UpdateProgressSnapshot(items: items)
    }

    private func finalizeUpdateResult(_ result: UpdateResult, greedy: Bool) async throws -> UpdateResult {
        statusMessage = "Verifying updates..."
        let refreshedOutdatedPackages = try await brewService.checkOutdated(greedy: greedy || greedyModeEnabled)
        markVerifiedProgress(result: result, stillOutdated: refreshedOutdatedPackages)
        let observedResult = result.supplemented(with: updateProgress?.items ?? [])
        let completedResult = observedResult.excludingPackagesStillOutdated(refreshedOutdatedPackages)

        if !completedResult.isEmpty {
            lastUpdateResult = completedResult
            addToHistory(completedResult)
        }
        outdatedPackages = refreshedOutdatedPackages
        skippedPackages = []

        return completedResult
    }

    private func markVerifiedProgress(result: UpdateResult, stillOutdated: [OutdatedPackage]) {
        guard var items = updateProgress?.items else { return }

        let parsedCompletedNames = Set(result.packages.map(\.name))
        let stillOutdatedNames = Set(stillOutdated.map(\.name))

        for index in items.indices {
            if stillOutdatedNames.contains(items[index].name) {
                items[index].state = .attempted
            } else if parsedCompletedNames.contains(items[index].name) || items[index].state == .attempted {
                items[index].state = .finished
            }
        }

        updateProgress = UpdateProgressSnapshot(items: items)
    }

    private func completionMessage(for result: UpdateResult, remainingCount: Int) -> String {
        if result.isEmpty {
            if remainingCount > 0 {
                return "No packages completed. \(remainingCount) item\(remainingCount == 1 ? "" : "s") still need updates."
            }
            return "Everything is up to date!"
        }

        var message = "\(result.count) package\(result.count == 1 ? "" : "s") upgraded"
        if remainingCount > 0 {
            message += ". \(remainingCount) item\(remainingCount == 1 ? "" : "s") still need updates."
        }
        return message
    }

    func startPeriodicChecks() {
        stopPeriodicChecks()

        guard checkInterval > 0 else { return }

        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdates()
            }
        }
    }

    func stopPeriodicChecks() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func startPeriodicAppUpdateChecks() {
        appUpdateCheckTimer?.invalidate()
        appUpdateCheckTimer = Timer.scheduledTimer(withTimeInterval: Self.appUpdateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appUpdateInfo = await self.updateChecker.checkForUpdate()
            }
        }
    }

    private func restartPeriodicChecks() {
        startPeriodicChecks()
    }

    private func startNetworkMonitoring() {
        networkMonitor.startMonitoring { [weak self] in
            guard let self else { return }
            // Only trigger check if initial check failed due to no connectivity
            if !self.initialCheckSucceeded {
                self.initialCheckSucceeded = true  // Prevent repeated triggers
                Task { @MainActor in
                    await self.checkForUpdates()
                }
            }
        }
    }

    private func showSuccessAnimation() async {
        // Checkmark for 1 second
        iconState = .checkmark
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Full mug - everything is up to date after upgrade
        iconState = .upToDate
    }

    private func startIconAnimation() {
        // No-op. The previous timer-based approach published a new NSImage
        // onto `spinnerFrame` every 100 ms, which made `objectWillChange`
        // fire constantly and forced the menu tree to reconcile 10× per
        // second — breaking NSMenu's hover-to-open-submenu delay. The
        // visual spinning is now handled by a SwiftUI animation in the
        // `SpinningArrowsLabel` view in `TopOffApp.swift`, which keeps its
        // rotation state local and does not invalidate the menu content.
    }

    private func stopIconAnimation() {
        // No-op (see startIconAnimation).
    }

    private static func generateSpinnerFrames(frameCount: Int = 12, pointSize: CGFloat = 16) -> [NSImage] {
        guard let baseSymbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) else {
            return []
        }

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let configured = baseSymbol.withSymbolConfiguration(config) else { return [] }

        let size = configured.size

        return (0..<frameCount).compactMap { i in
            let angle = -CGFloat(i) * (2.0 * .pi / CGFloat(frameCount))

            let image = NSImage(size: size, flipped: false) { _ in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: angle)
                ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
                configured.draw(in: NSRect(origin: .zero, size: size))
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    private func updateLaunchAtLogin() {
        loginItemManager.setEnabled(launchAtLogin)
    }

    // MARK: - Update History

    func addToHistory(_ result: UpdateResult) {
        guard !result.isEmpty else { return }
        updateHistory.insert(result, at: 0)
        if updateHistory.count > 20 {
            updateHistory = Array(updateHistory.prefix(20))
        }
    }

    private func saveUpdateHistory() {
        if let encoded = try? JSONEncoder().encode(updateHistory) {
            defaults.set(encoded, forKey: "updateHistory")
        }
    }

    private func loadUpdateHistory() {
        if let data = defaults.data(forKey: "updateHistory"),
           let decoded = try? JSONDecoder().decode([UpdateResult].self, from: data) {
            // Heal records written by the pre-fix parser (malformed names,
            // empty old versions, duplicate "?" rows). Assigning back through
            // the `didSet` re-persists the cleaned history, so this runs once.
            let sanitized = decoded.map { $0.sanitized() }
            updateHistory = sanitized
            lastUpdateResult = sanitized.first
        }
    }

    private func saveRememberedSkipList() {
        let sorted = rememberedSkipList.sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            defaults.set(data, forKey: "rememberedSkipList")
        }
    }

    private static func loadRememberedSkipList(from defaults: UserDefaults) -> Set<String> {
        guard let data = defaults.data(forKey: "rememberedSkipList"),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(array)
    }

}
