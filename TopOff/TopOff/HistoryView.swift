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
                List(viewModel.updateHistory, id: \.timestamp) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(formatDate(result.timestamp))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(result.packages) { package in
                            Text("\(package.name) \(package.oldVersion) → \(package.newVersion)")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }

            Divider()

            Button("Clear History") {
                viewModel.updateHistory = []
            }
            .disabled(viewModel.updateHistory.isEmpty)
            .padding()
        }
        .frame(width: 320, height: 400)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today at \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Yesterday at \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}
