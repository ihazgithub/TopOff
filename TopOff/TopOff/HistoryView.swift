import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: 0) {
            Text("Update History")
                .font(.headline)
                .padding()

            Divider()

            if viewModel.updateHistory.isEmpty {
                Spacer()
                Text("No updates yet")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(HistoryGrouping.groupHistory(viewModel.updateHistory)) { group in
                        Section {
                            ForEach(group.events, id: \.timestamp) { event in
                                eventRow(event)
                            }
                        } header: {
                            Text(group.title)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            Button("Clear History") {
                viewModel.updateHistory = []
            }
            .disabled(viewModel.updateHistory.isEmpty)
            .padding()
        }
        .frame(width: 360, height: 500)
    }

    @ViewBuilder
    private func eventRow(_ event: UpdateResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(timeLabel(for: event))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(event.packages) { package in
                HStack(spacing: 8) {
                    Text(package.name)
                        .fontWeight(.medium)
                    Spacer(minLength: 8)
                    if package.hasKnownNewVersion {
                        Text(versionTransition(package))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func timeLabel(for event: UpdateResult) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let timeString = formatter.string(from: event.timestamp)
        let count = event.packages.count
        return "\(timeString) · \(count) package\(count == 1 ? "" : "s")"
    }

    private func versionTransition(_ package: UpgradedPackage) -> String {
        let from = DisplayVersion.abbreviate(package.oldVersion)
        let to   = DisplayVersion.abbreviate(package.newVersion)
        return "\(from) → \(to)"
    }
}
