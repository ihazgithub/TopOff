import SwiftUI

/// Full list of outdated packages. The menu only shows the first five, so
/// this window is where the rest can be seen, updated, or skipped.
struct OutdatedPackagesView: View {
    @EnvironmentObject private var viewModel: MenuBarViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let packages = viewModel.visibleOutdatedPackages

        VStack(spacing: 0) {
            Text("Outdated Packages")
                .font(.headline)
                .padding()

            Divider()

            if packages.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("All packages up to date")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(packages) { package in
                    packageRow(package)
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if !packages.isEmpty {
                    Text("\(packages.count) package\(packages.count == 1 ? "" : "s")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(viewModel.greedyModeEnabled ? "Update All (Greedy)" : "Update All") {
                    viewModel.updateAll(greedy: viewModel.greedyModeEnabled)
                }
                .disabled(packages.isEmpty || viewModel.isRunning)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 460)
    }

    @ViewBuilder
    private func packageRow(_ package: OutdatedPackage) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(package.name)
                    .fontWeight(.medium)
                Text(versionTransition(package))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if isUpdating(package) {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Update") {
                viewModel.upgradePackage(package)
            }
            .disabled(viewModel.isRunning)
            .help("Update \(package.name) now")

            // Skip stays available during updates, matching the menu.
            Button("Skip") {
                viewModel.skipPackage(package)
            }
            .help(viewModel.rememberSkippedPackages
                  ? "Skip \(package.name) until you remove it from Skipped Packages"
                  : "Hide \(package.name) until the next check")
        }
        .padding(.vertical, 2)
    }

    private func isUpdating(_ package: OutdatedPackage) -> Bool {
        if viewModel.packageBeingUpgraded == package.name { return true }
        guard let item = viewModel.updateProgress?.items.first(where: { $0.name == package.name }) else {
            return false
        }
        return item.state == .updating || item.state == .repairing
    }

    private func versionTransition(_ package: OutdatedPackage) -> String {
        let from = DisplayVersion.abbreviate(package.currentVersion)
        let to   = DisplayVersion.abbreviate(package.latestVersion)
        return "\(from) → \(to)"
    }
}
