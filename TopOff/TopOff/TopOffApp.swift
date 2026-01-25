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
                Button {
                    viewModel.checkInterval = 3600
                } label: {
                    if viewModel.checkInterval == 3600 { Text("✓ Every hour") }
                    else { Text("    Every hour") }
                }
                Button {
                    viewModel.checkInterval = 14400
                } label: {
                    if viewModel.checkInterval == 14400 { Text("✓ Every 4 hours") }
                    else { Text("    Every 4 hours") }
                }
                Button {
                    viewModel.checkInterval = 43200
                } label: {
                    if viewModel.checkInterval == 43200 { Text("✓ Every 12 hours") }
                    else { Text("    Every 12 hours") }
                }
                Button {
                    viewModel.checkInterval = 86400
                } label: {
                    if viewModel.checkInterval == 86400 { Text("✓ Every 24 hours") }
                    else { Text("    Every 24 hours") }
                }
                Button {
                    viewModel.checkInterval = 0
                } label: {
                    if viewModel.checkInterval == 0 { Text("✓ Manual only") }
                    else { Text("    Manual only") }
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
