import SwiftUI
import ServiceManagement

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
    @Published var iconState: MenuBarIconState = .upToDate
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
    @Published var selectiveUpdatesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(selectiveUpdatesEnabled, forKey: "selectiveUpdatesEnabled")
        }
    }
    @Published var autoCleanupEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCleanupEnabled, forKey: "autoCleanupEnabled")
        }
    }

    @Published var appUpdateInfo: AppUpdateInfo?
    @Published var isCheckingForAppUpdate = false
    @Published var appUpdateChecked = false

    private let brewService = BrewService()
    private let updateChecker = UpdateChecker()
    private let notificationManager = NotificationManager.shared
    private var checkTimer: Timer?

    init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.checkInterval = UserDefaults.standard.object(forKey: "checkInterval") as? TimeInterval ?? 14400
        self.selectiveUpdatesEnabled = UserDefaults.standard.bool(forKey: "selectiveUpdatesEnabled")
        // Default to true for auto cleanup — UserDefaults.bool returns false if key doesn't exist
        if UserDefaults.standard.object(forKey: "autoCleanupEnabled") == nil {
            self.autoCleanupEnabled = true
        } else {
            self.autoCleanupEnabled = UserDefaults.standard.bool(forKey: "autoCleanupEnabled")
        }
        notificationManager.requestPermission()

        // Check for updates on launch
        Task {
            await checkForUpdates()
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
                let result = try await brewService.updateAll(greedy: greedy)
                lastUpdateResult = result
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
                statusMessage = nil
                iconState = outdatedPackages.isEmpty ? .upToDate : .updatesAvailable
                notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
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
                statusMessage = nil
                updateIconState()
                notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
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

    func checkForUpdates() async {
        guard !isRunning else { return }

        isRunning = true
        iconState = .checking
        statusMessage = "Checking for updates..."

        do {
            outdatedPackages = try await brewService.checkOutdated()
            skippedPackages = []
            updateIconState()
        } catch {
            iconState = .upToDate
            print("Failed to check for updates: \(error)")
        }

        statusMessage = nil
        isRunning = false
    }

    func checkForAppUpdate() {
        Task {
            isCheckingForAppUpdate = true
            appUpdateInfo = await updateChecker.checkForUpdate()
            isCheckingForAppUpdate = false
            appUpdateChecked = true
        }
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

    private func showSuccessAnimation() async {
        // Checkmark for 1 second
        iconState = .checkmark
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Full mug - everything is up to date after upgrade
        iconState = .upToDate
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
}
