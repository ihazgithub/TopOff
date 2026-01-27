import SwiftUI

@main
struct TopOffApp: App {
    @StateObject private var viewModel = MenuBarViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            // Active status line
            if let status = viewModel.statusMessage {
                Text(status)
                    .foregroundStyle(.secondary)
                Divider()
            }

            // Outdated packages with version details
            if !viewModel.visibleOutdatedPackages.isEmpty {
                let visible = viewModel.visibleOutdatedPackages
                let displayPackages = Array(visible.prefix(5))
                let overflow = visible.count - displayPackages.count

                if viewModel.selectiveUpdatesEnabled {
                    ForEach(displayPackages) { package in
                        Menu("\(package.name)  \(package.currentVersion) → \(package.latestVersion)") {
                            Button("Update") {
                                viewModel.upgradePackage(package)
                            }
                            Button("Skip") {
                                viewModel.skipPackage(package)
                            }
                        }
                        .disabled(viewModel.isRunning)
                    }
                } else {
                    ForEach(displayPackages) { package in
                        Text("\(package.name)  \(package.currentVersion) → \(package.latestVersion)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if overflow > 0 {
                    Text("...and \(overflow) more")
                        .foregroundStyle(.secondary)
                }

                Divider()
            }

            // Primary actions
            Button("Update All") {
                viewModel.updateAll(greedy: false)
            }
            .disabled(viewModel.isRunning)

            Button("Update All (Greedy)") {
                viewModel.updateAll(greedy: true)
            }
            .disabled(viewModel.isRunning)

            // Manual cleanup button (only when auto cleanup is off)
            if !viewModel.autoCleanupEnabled {
                Button("Clean Up") {
                    viewModel.runCleanup()
                }
                .disabled(viewModel.isRunning)
            }

            Button("Check for Updates") {
                Task {
                    await viewModel.checkForUpdates()
                }
            }
            .disabled(viewModel.isRunning)

            Divider()

            // Last Update Results
            if let result = viewModel.lastUpdateResult {
                if result.isEmpty {
                    Text("Last Update: No changes")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Last Update (\(result.count) package\(result.count == 1 ? "" : "s")):")
                        .foregroundStyle(.secondary)
                    ForEach(result.packages) { package in
                        Text("  \(package.name) \(package.oldVersion) → \(package.newVersion)")
                            .font(.system(.body, design: .monospaced))
                    }
                }

                if let cleanup = viewModel.lastCleanupResult, !cleanup.freedSpace.isEmpty {
                    Text("  Cleanup: Freed \(cleanup.freedSpace)")
                        .foregroundStyle(.secondary)
                }

                Divider()
            }

            // Settings submenu
            Menu("Settings") {
                Toggle("Selective Updates", isOn: $viewModel.selectiveUpdatesEnabled)
                Toggle("Auto Cleanup", isOn: $viewModel.autoCleanupEnabled)
                Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)

                Divider()

                Picker("Check Interval", selection: $viewModel.checkInterval) {
                    Text("Every Hour").tag(3600.0 as TimeInterval)
                    Text("Every 4 Hours").tag(14400.0 as TimeInterval)
                    Text("Every 12 Hours").tag(43200.0 as TimeInterval)
                    Text("Every 24 Hours").tag(86400.0 as TimeInterval)
                    Text("Manual Only").tag(0.0 as TimeInterval)
                }
            }

            Divider()

            Button(viewModel.appUpdateInfo != nil ? "About TopOff (Update Available)" : "About TopOff") {
                openWindow(id: "about")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Quit TopOff") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            if viewModel.iconState.isCustomImage {
                Image(viewModel.iconState.imageName)
            } else {
                Image(systemName: viewModel.iconState.imageName)
                    .symbolEffect(.pulse, isActive: viewModel.iconState == .checking || viewModel.iconState == .updating)
            }
        }

        Window("About TopOff", id: "about") {
            AboutView()
                .environmentObject(viewModel)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
