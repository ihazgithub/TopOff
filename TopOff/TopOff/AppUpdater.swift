import Combine
import Foundation
import Sparkle

/// Thin wrapper around Sparkle's standard updater controller.
///
/// Sparkle owns the entire update lifecycle — appcast fetch, EdDSA
/// signature verification, download, install, and relaunch — configured
/// by the `SUFeedURL` / `SUPublicEDKey` keys in Info.plist. Scheduled
/// background checks run on `SUScheduledCheckInterval`. This class only
/// exposes what the UI needs: a "check now" entry point and a published
/// flag for enabling/disabling menu items.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    /// Mirrors `SPUUpdater.canCheckForUpdates` — false while a check or
    /// install is already in flight.
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true kicks off Sparkle's scheduled background
        // checks immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// User-initiated check — presents Sparkle's standard UI, including
    /// the "you're up to date" confirmation.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
