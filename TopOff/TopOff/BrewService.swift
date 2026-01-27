import Foundation

enum BrewError: Error, LocalizedError {
    case brewNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Homebrew not found. Please install Homebrew first."
        case .commandFailed(let message):
            return "Brew command failed: \(message)"
        }
    }
}

struct OutdatedPackage: Identifiable {
    let id = UUID()
    let name: String
    let currentVersion: String
    let latestVersion: String
}

struct UpgradedPackage: Identifiable {
    let id = UUID()
    let name: String
    let oldVersion: String
    let newVersion: String
}

struct UpdateResult {
    let packages: [UpgradedPackage]
    let timestamp: Date

    var isEmpty: Bool { packages.isEmpty }
    var count: Int { packages.count }
}

struct CleanupResult {
    let freedSpace: String
    let timestamp: Date
}

@MainActor
final class BrewService {
    let brewPath: String?

    init() {
        self.brewPath = Self.findBrewPath()
    }

    static func findBrewPath() -> String? {
        let appleSiliconPath = "/opt/homebrew/bin/brew"
        let intelPath = "/usr/local/bin/brew"

        if FileManager.default.fileExists(atPath: appleSiliconPath) {
            return appleSiliconPath
        } else if FileManager.default.fileExists(atPath: intelPath) {
            return intelPath
        }
        return nil
    }

    func findBrewPath() -> String? {
        Self.findBrewPath()
    }

    func checkOutdated() async throws -> [OutdatedPackage] {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        // Run brew update first to refresh package info
        _ = try await runCommand(brewPath, arguments: ["update"])

        // Then check what's outdated with verbose output for version info
        let output = try await runCommand(brewPath, arguments: ["outdated", "--verbose"])
        return parseOutdatedVerbose(output)
    }

    func updateAll(greedy: Bool = false) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        // Run brew update
        _ = try await runCommand(brewPath, arguments: ["update"])

        // Run brew upgrade
        var upgradeArgs = ["upgrade"]
        if greedy {
            upgradeArgs.append("--greedy")
        }
        let upgradeOutput = try await runCommand(brewPath, arguments: upgradeArgs)

        // Parse the upgrade output to find upgraded packages
        let packages = parseUpgradeOutput(upgradeOutput)
        return UpdateResult(packages: packages, timestamp: Date())
    }

    private func parseUpgradeOutput(_ output: String) -> [UpgradedPackage] {
        var packages: [UpgradedPackage] = []

        // Look for lines like "==> Upgrading foo 1.0 -> 2.0" or "foo 1.0 -> 2.0"
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Match patterns like "package 1.0 -> 2.0" or "==> Upgrading package 1.0 -> 2.0"
            if line.contains(" -> ") {
                let cleanLine = line.replacingOccurrences(of: "==> Upgrading ", with: "")
                                    .replacingOccurrences(of: "==> ", with: "")
                                    .trimmingCharacters(in: .whitespaces)

                let parts = cleanLine.components(separatedBy: " -> ")
                if parts.count == 2 {
                    let leftParts = parts[0].components(separatedBy: " ")
                    if leftParts.count >= 2 {
                        let name = leftParts.dropLast().joined(separator: " ")
                        let oldVersion = leftParts.last ?? ""
                        let newVersion = parts[1].trimmingCharacters(in: .whitespaces)

                        packages.append(UpgradedPackage(
                            name: name,
                            oldVersion: oldVersion,
                            newVersion: newVersion
                        ))
                    }
                }
            }
        }

        return packages
    }

    private func parseOutdatedVerbose(_ output: String) -> [OutdatedPackage] {
        // brew outdated --verbose outputs lines like:
        // node (20.1.0) < 22.0.0
        // python@3.12 (3.11.4) < 3.12.1
        var packages: [OutdatedPackage] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains(" < ") else { continue }

            let parts = trimmed.components(separatedBy: " < ")
            guard parts.count == 2 else { continue }

            let latestVersion = parts[1].trimmingCharacters(in: .whitespaces)
            let leftSide = parts[0]

            // Extract name and current version from "name (version)"
            if let parenOpen = leftSide.lastIndex(of: "("),
               let parenClose = leftSide.lastIndex(of: ")") {
                let name = String(leftSide[leftSide.startIndex..<parenOpen]).trimmingCharacters(in: .whitespaces)
                let currentVersion = String(leftSide[leftSide.index(after: parenOpen)..<parenClose])
                packages.append(OutdatedPackage(name: name, currentVersion: currentVersion, latestVersion: latestVersion))
            } else {
                // Fallback: treat everything before " < " as name, no current version
                let name = leftSide.trimmingCharacters(in: .whitespaces)
                packages.append(OutdatedPackage(name: name, currentVersion: "?", latestVersion: latestVersion))
            }
        }

        return packages
    }

    func upgradePackage(_ name: String) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        let upgradeOutput = try await runCommand(brewPath, arguments: ["upgrade", name])
        let packages = parseUpgradeOutput(upgradeOutput)
        return UpdateResult(packages: packages, timestamp: Date())
    }

    func cleanup() async throws -> CleanupResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        let output = try await runCommand(brewPath, arguments: ["cleanup"])
        return parseCleanupOutput(output)
    }

    private func parseCleanupOutput(_ output: String) -> CleanupResult {
        // Look for the summary line: "==> This operation has freed approximately 401.7MB of disk space."
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if line.contains("freed approximately") {
                // Extract the size value between "approximately " and " of disk space"
                if let approxRange = line.range(of: "approximately "),
                   let ofRange = line.range(of: " of disk space") {
                    let freedSpace = String(line[approxRange.upperBound..<ofRange.lowerBound])
                    return CleanupResult(freedSpace: freedSpace, timestamp: Date())
                }
            }
        }

        // If no summary line found, cleanup may have had nothing to do
        return CleanupResult(freedSpace: "", timestamp: Date())
    }

    private func runCommand(_ command: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            // Set up environment to find brew dependencies
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "")
            process.environment = environment

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: BrewError.commandFailed(output))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
