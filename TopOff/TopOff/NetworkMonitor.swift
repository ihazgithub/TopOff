import Foundation
import Network

/// Monitors network connectivity and notifies when connection is restored.
/// Used to trigger update checks when the app starts without internet access.
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var isConnected = false
    private var onConnectionRestored: (() -> Void)?

    /// Starts monitoring for network connectivity changes.
    /// - Parameter onConnectionRestored: Called once when network becomes available after being unavailable.
    func startMonitoring(onConnectionRestored: @escaping () -> Void) {
        self.onConnectionRestored = onConnectionRestored

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            let wasConnected = self.isConnected
            self.isConnected = path.status == .satisfied

            // Trigger callback when transitioning from disconnected to connected
            if !wasConnected && self.isConnected {
                DispatchQueue.main.async {
                    self.onConnectionRestored?()
                }
            }
        }

        monitor.start(queue: queue)
    }

    /// Stops monitoring and clears the callback.
    func stopMonitoring() {
        monitor.cancel()
        onConnectionRestored = nil
    }

    deinit {
        stopMonitoring()
    }
}
