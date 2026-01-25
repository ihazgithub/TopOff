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

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: viewModel.iconState.systemImage)
                .symbolEffect(.pulse, isActive: viewModel.iconState == .running)
        }
    }
}
