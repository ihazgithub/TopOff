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
            UserDefaults.standard.set(checkInterval, forKey: "checkInterval")
            restartPeriodicChecks()
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }
    @Published var autoCleanupEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCleanupEnabled, forKey: "autoCleanupEnabled")
        }
    }
    @Published var greedyModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(greedyModeEnabled, forKey: "greedyModeEnabled")
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

    private let brewService = BrewService()
    private let updateChecker = UpdateChecker()
    private let notificationManager = NotificationManager.shared
    private let networkMonitor = NetworkMonitor()
    private var checkTimer: Timer?
    private var appUpdateCheckTimer: Timer?
    private var iconAnimationTimer: Timer?
    private var spinnerFrames: [NSImage] = []
    private var spinnerFrameIndex = 0
    private var initialCheckSucceeded = false

    init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.checkInterval = UserDefaults.standard.object(forKey: "checkInterval") as? TimeInterval ?? 14400
        // Default to true for auto cleanup — UserDefaults.bool returns false if key doesn't exist
        if UserDefaults.standard.object(forKey: "autoCleanupEnabled") == nil {
            self.autoCleanupEnabled = true
        } else {
            self.autoCleanupEnabled = UserDefaults.standard.bool(forKey: "autoCleanupEnabled")
        }
        self.greedyModeEnabled = UserDefaults.standard.bool(forKey: "greedyModeEnabled")
        spinnerFrames = Self.generateSpinnerFrames()
        loadUpdateHistory()
        UserDefaults.standard.removeObject(forKey: "packagesNeedingAttention")
        notificationManager.requestPermission()

        // Start network monitor to handle connectivity restoration
        startNetworkMonitoring()

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

    /// Visible outdated packages (excludes skipped)
    var visibleOutdatedPackages: [OutdatedPackage] {
        outdatedPackages.filter { !skippedPackages.contains($0.name) }
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
                    statusMessage = "Cleaning up..."
                    lastCleanupResult = try? await brewService.cleanup()
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
                if brewService.isPermissionError(errorOutput) && promptForAdminRetry(packageName: nil) {
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
                            statusMessage = "Cleaning up..."
                            lastCleanupResult = try? await brewService.cleanup()
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
                        notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
                    }
                } else {
                    statusMessage = nil
                    updateProgress = nil
                    iconState = outdatedPackages.isEmpty ? .upToDate : .updatesAvailable
                    notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
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
                let result = try await brewService.upgradePackage(package.name)

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
                    statusMessage = "Cleaning up..."
                    lastCleanupResult = try? await brewService.cleanup()
                }

                statusMessage = nil
                updateIconState()

                let message = "\(package.name) upgraded"
                notificationManager.showCompletionNotification(success: true, message: message)
            } catch {
                let errorOutput = extractErrorOutput(from: error)
                if brewService.isPermissionError(errorOutput) && promptForAdminRetry(packageName: package.name) {
                    do {
                        statusMessage = "Retrying \(package.name) with admin privileges..."
                        let result = try await brewService.upgradePackageWithAdmin(package.name)

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
                            statusMessage = "Cleaning up..."
                            lastCleanupResult = try? await brewService.cleanup()
                        }

                        statusMessage = nil
                        updateIconState()

                        let message = "\(package.name) upgraded"
                        notificationManager.showCompletionNotification(success: true, message: message)
                    } catch {
                        statusMessage = nil
                        updateIconState()
                        notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
                    }
                } else {
                    statusMessage = nil
                    updateIconState()
                    notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
                }
            }

            isRunning = false
        }
    }

    func skipPackage(_ package: OutdatedPackage) {
        skippedPackages.insert(package.name)
        updateIconState()
    }

    func runCleanup() {
        guard !isRunning else { return }

        Task {
            isRunning = true
            statusMessage = "Cleaning up..."

            do {
                lastCleanupResult = try await brewService.cleanup()
                statusMessage = nil

                let message: String
                if let result = lastCleanupResult, !result.freedSpace.isEmpty {
                    message = "Freed \(result.freedSpace)"
                } else {
                    message = "Nothing to clean up"
                }
                notificationManager.showCompletionNotification(success: true, message: message)
            } catch {
                statusMessage = nil
                notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
            }

            isRunning = false
        }
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

    private func promptForAdminRetry(packageName: String?) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Administrator Access Required"
        if let name = packageName {
            alert.informativeText = "\"\(name)\" needs administrator access to update. This will open the macOS password dialog."
        } else {
            alert.informativeText = "Some packages need administrator access to update. This will open the macOS password dialog."
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Retry with Admin")
        alert.addButton(withTitle: "Cancel")
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
            }
        }
        return error.localizedDescription
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
                    packageNames: regularPackages.map(\.name),
                    onProgress: progressHandler
                )
            } else {
                result = try await brewService.updateAll(
                    greedy: greedy,
                    packageNames: regularPackages.map(\.name),
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
        iconAnimationTimer?.invalidate()
        spinnerFrameIndex = 0
        spinnerFrame = spinnerFrames.first
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.spinnerFrames.isEmpty else { return }
                self.spinnerFrameIndex = (self.spinnerFrameIndex + 1) % self.spinnerFrames.count
                self.spinnerFrame = self.spinnerFrames[self.spinnerFrameIndex]
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        iconAnimationTimer = timer
    }

    private func stopIconAnimation() {
        iconAnimationTimer?.invalidate()
        iconAnimationTimer = nil
        spinnerFrame = nil
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
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
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
            UserDefaults.standard.set(encoded, forKey: "updateHistory")
        }
    }

    private func loadUpdateHistory() {
        if let data = UserDefaults.standard.data(forKey: "updateHistory"),
           let decoded = try? JSONDecoder().decode([UpdateResult].self, from: data) {
            updateHistory = decoded
            lastUpdateResult = decoded.first
        }
    }

}
