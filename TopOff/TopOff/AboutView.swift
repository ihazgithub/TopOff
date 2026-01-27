import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var viewModel: MenuBarViewModel

    private let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2"
    }()

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("TopOff")
                .font(.title.bold())

            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)

            if let update = viewModel.appUpdateInfo {
                Link("Update Available — v\(update.latestVersion)", destination: update.downloadURL)
                    .font(.callout.weight(.medium))
            } else if viewModel.isCheckingForAppUpdate {
                ProgressView()
                    .controlSize(.small)
            } else if viewModel.appUpdateChecked {
                Text("App is up to date")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                Button("Check for Updates") {
                    viewModel.checkForAppUpdate()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .font(.callout)
            }

            Spacer().frame(height: 4)

            Text("Created by Thomas Haslam")
            Text("Copyright \u{00A9} 2026 TopOff")
                .foregroundStyle(.secondary)
                .font(.caption)

            Spacer().frame(height: 4)

            Link(destination: URL(string: "https://ko-fi.com/squamthomas")!) {
                HStack(spacing: 6) {
                    Image(systemName: "cup.and.saucer.fill")
                    Text("Buy Me a Coffee")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.blue)
                .foregroundStyle(.white)
                .cornerRadius(8)
            }

            Spacer()
        }
        .frame(width: 280, height: 340)
    }
}
