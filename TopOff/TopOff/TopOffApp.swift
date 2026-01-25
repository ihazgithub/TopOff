import SwiftUI

@main
struct TopOffApp: App {
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            Button("Update All") {
                viewModel.updateAll(greedy: false)
            }
            .disabled(viewModel.isRunning)

            Button("Update All (Greedy)") {
                viewModel.updateAll(greedy: true)
            }
            .disabled(viewModel.isRunning)

            Divider()

            Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)

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
                    .symbolEffect(.pulse, isActive: viewModel.iconState == .running)
            }
        }
    }
}
