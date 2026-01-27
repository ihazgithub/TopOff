import Foundation

struct AppUpdateInfo {
    let latestVersion: String
    let downloadURL: URL
}

final class UpdateChecker {
    private let owner = "ihazgithub"
    private let repo = "TopOff"

    func checkForUpdate() async -> AppUpdateInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String,
                  let downloadURL = URL(string: htmlURL) else {
                return nil
            }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"

            guard isVersion(latestVersion, newerThan: currentVersion) else {
                return nil
            }

            return AppUpdateInfo(latestVersion: latestVersion, downloadURL: downloadURL)
        } catch {
            return nil
        }
    }

    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(aParts.count, bParts.count)
        for i in 0..<maxLength {
            let aVal = i < aParts.count ? aParts[i] : 0
            let bVal = i < bParts.count ? bParts[i] : 0
            if aVal > bVal { return true }
            if aVal < bVal { return false }
        }
        return false
    }
}
