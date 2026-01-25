import SwiftUI
import ServiceManagement

enum MenuBarIconState {
    case idle        // Half-filled mug
    case running     // Spinner
    case checkmark   // Brief checkmark
    case complete    // Full mug

    var systemImage: String {
        switch self {
        case .idle:
            return "mug"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .checkmark:
            return "checkmark.circle.fill"
        case .complete:
            return "mug.fill"
        }
    }
}

@MainActor
class MenuBarViewModel: ObservableObject {
    @Published var iconState: MenuBarIconState = .idle
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    private let brewService = BrewService()
    private let notificationManager = NotificationManager.shared

    var isRunning: Bool {
        brewService.isRunning
    }

    init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        notificationManager.requestPermission()
    }

    func updateAll(greedy: Bool) {
        Task {
            iconState = .running

            do {
                _ = try await brewService.updateAll(greedy: greedy)
                await showSuccessAnimation()
                notificationManager.showCompletionNotification(success: true, message: "")
            } catch {
                iconState = .idle
                notificationManager.showCompletionNotification(success: false, message: error.localizedDescription)
            }
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
