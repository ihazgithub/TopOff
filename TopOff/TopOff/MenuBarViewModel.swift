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
    @Published private(set) var isRunning = false
    @Published var outdatedPackages: [String] = []
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

    private let brewService = BrewService()
    private let notificationManager = NotificationManager.shared
    private var checkTimer: Timer?

    init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.checkInterval = UserDefaults.standard.object(forKey: "checkInterval") as? TimeInterval ?? 14400
        notificationManager.requestPermission()

        // Check for updates on launch
        Task {
            await checkForUpdates()
            startPeriodicChecks()
        }
    }

    func updateAll(greedy: Bool) {
        guard !isRunning else { return }

        Task {
            isRunning = true
            iconState = .updating

            do {
                let result = try await brewService.updateAll(greedy: greedy)
                lastUpdateResult = result
                outdatedPackages = []
                await showSuccessAnimation()

                let message = result.isEmpty
                    ? "Everything is up to date!"
                    : "\(result.count) package\(result.count == 1 ? "" : "s") upgraded"
                notificationManager.showCompletionNotification(success: true, message: message)
            } catch {
                iconState = outdatedPackages.isEmpty ? .upToDate : .updatesAvailable
                notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
            }

            isRunning = false
        }
    }

    func checkForUpdates() async {
        guard !isRunning else { return }

        isRunning = true
        iconState = .checking

        do {
            outdatedPackages = try await brewService.checkOutdated()
            iconState = outdatedPackages.isEmpty ? .upToDate : .updatesAvailable
        } catch {
            iconState = .upToDate
            print("Failed to check for updates: \(error)")
        }

        isRunning = false
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
