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
            iconState = .updating
            statusMessage = "Updating packages..."

            do {
                let result = try await brewService.updateAll(greedy: greedy) { [weak self] line in
                    if line.contains("==> Upgrading") {
                        let name = line.replacingOccurrences(of: "==> Upgrading ", with: "")
                            .components(separatedBy: " ").first ?? ""
                        if !name.isEmpty {
                            Task { @MainActor in
                                self?.statusMessage = "Updating \(name)..."
                            }
                        }
                    }
                }
                lastUpdateResult = result
                addToHistory(result)
                outdatedPackages = []
                skippedPackages = []

                // Run cleanup if auto cleanup is enabled
                if autoCleanupEnabled {
                    statusMessage = "Cleaning up..."
                    lastCleanupResult = try? await brewService.cleanup()
                }

                statusMessage = nil
                await showSuccessAnimation()

                var message = result.isEmpty
                    ? "Everything is up to date!"
                    : "\(result.count) package\(result.count == 1 ? "" : "s") upgraded"
                if let cleanup = lastCleanupResult, !cleanup.freedSpace.isEmpty {
                    message += ". Freed \(cleanup.freedSpace)"
                }
                notificationManager.showCompletionNotification(success: true, message: message)
            } catch {
                let errorOutput = extractErrorOutput(from: error)
                if brewService.isPermissionError(errorOutput) && promptForAdminRetry(packageName: nil) {
                    do {
                        statusMessage = "Retrying with admin privileges..."
                        let result = try await brewService.updateAllWithAdmin(greedy: greedy) { [weak self] line in
                            if line.contains("==> Upgrading") {
                                let name = line.replacingOccurrences(of: "==> Upgrading ", with: "")
                                    .components(separatedBy: " ").first ?? ""
                                if !name.isEmpty {
                                    Task { @MainActor in
                                        self?.statusMessage = "Updating \(name)..."
                                    }
                                }
                            }
                        }
                        lastUpdateResult = result
                        addToHistory(result)
                        outdatedPackages = []
                        skippedPackages = []

                        if autoCleanupEnabled {
                            statusMessage = "Cleaning up..."
                            lastCleanupResult = try? await brewService.cleanup()
                        }

                        statusMessage = nil
                        await showSuccessAnimation()

                        var message = result.isEmpty
                            ? "Everything is up to date!"
                            : "\(result.count) package\(result.count == 1 ? "" : "s") upgraded"
                        if let cleanup = lastCleanupResult, !cleanup.freedSpace.isEmpty {
                            message += ". Freed \(cleanup.freedSpace)"
                        }
                        notificationManager.showCompletionNotification(success: true, message: message)
                    } catch {
                        statusMessage = nil
                        iconState = outdatedPackages.isEmpty ? .upToDate : .updatesAvailable
                        notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
                    }
                } else {
                    statusMessage = nil
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
            outdatedPackages = try await brewService.checkOutdated(greedy: greedyModeEnabled)
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
        iconAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.spinnerFrames.isEmpty else { return }
                self.spinnerFrameIndex = (self.spinnerFrameIndex + 1) % self.spinnerFrames.count
                self.spinnerFrame = self.spinnerFrames[self.spinnerFrameIndex]
            }
        }
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
        }
    }
}
