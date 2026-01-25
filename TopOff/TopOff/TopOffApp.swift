import SwiftUI

@main
struct TopOffApp: App {
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            // Outdated packages count
            if !viewModel.outdatedPackages.isEmpty {
                Text("\(viewModel.outdatedPackages.count) update\(viewModel.outdatedPackages.count == 1 ? "" : "s") available")
                    .foregroundStyle(.secondary)
                Divider()
            }

            Button("Update All") {
                viewModel.updateAll(greedy: false)
            }
            .disabled(viewModel.isRunning)

            Button("Update All (Greedy)") {
                viewModel.updateAll(greedy: true)
            }
            .disabled(viewModel.isRunning)

            Button("Check for Updates") {
                Task {
                    await viewModel.checkForUpdates()
                }
            }
            .disabled(viewModel.isRunning)

            Divider()

            Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)

            Menu("Check Interval") {
                Picker("", selection: $viewModel.checkInterval) {
                    Text("Every hour").tag(3600.0)
                    Text("Every 4 hours").tag(14400.0)
                    Text("Every 12 hours").tag(43200.0)
                    Text("Every 24 hours").tag(86400.0)
                    Text("Manual only").tag(0.0)
                }
            }

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
                        Text("  ✓ \(package.name) \(package.oldVersion) → \(package.newVersion)")
                            .font(.system(.body, design: .monospaced))
                    }
                }
                Divider()
            }

            Button("Quit") {
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
    }
}
