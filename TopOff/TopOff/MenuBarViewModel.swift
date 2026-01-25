import SwiftUI
import ServiceManagement

enum MenuBarIconState {
    case idle        // Half-filled beer mug (custom)
    case running     // Spinner (SF Symbol)
    case checkmark   // Brief checkmark (SF Symbol)
    case complete    // Full beer mug (custom)

    var isCustomImage: Bool {
        switch self {
        case .idle, .complete:
            return true
        case .running, .checkmark:
            return false
        }
    }

    var imageName: String {
        switch self {
        case .idle:
            return "MenuBarIcon"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .checkmark:
            return "checkmark.circle.fill"
        case .complete:
            return "MenuBarFull"
        }
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var iconState: MenuBarIconState = .idle
    @Published var lastUpdateResult: UpdateResult?
    @Published private(set) var isRunning = false
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    private let brewService = BrewService()
    private let notificationManager = NotificationManager.shared

    init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        notificationManager.requestPermission()
    }

    func updateAll(greedy: Bool) {
        guard !isRunning else { return }

        Task {
            isRunning = true
            iconState = .running

            do {
                let result = try await brewService.updateAll(greedy: greedy)
                lastUpdateResult = result
                await showSuccessAnimation()

                let message = result.isEmpty
                    ? "Everything is up to date!"
                    : "\(result.count) package\(result.count == 1 ? "" : "s") upgraded"
                notificationManager.showCompletionNotification(success: true, message: message)
            } catch {
                iconState = .idle
                notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
            }

            isRunning = false
        }
    }

    private func showSuccessAnimation() async {
        // Checkmark for 1 second
        iconState = .checkmark
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Full mug for 2 seconds
        iconState = .complete
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Back to idle
        iconState = .idle
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
