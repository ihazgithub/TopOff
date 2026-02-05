import Foundation

enum BrewError: Error, LocalizedError {
    case brewNotFound
    case commandFailed(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Homebrew not found. Please install Homebrew first."
        case .commandFailed(let message):
            return "Brew command failed: \(message)"
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        }
    }
}

struct OutdatedPackage: Identifiable {
    let id = UUID()
    let name: String
    let currentVersion: String
    let latestVersion: String
}

struct UpgradedPackage: Identifiable, Codable {
    let id: UUID
    let name: String
    let oldVersion: String
    let newVersion: String

    init(name: String, oldVersion: String, newVersion: String) {
        self.id = UUID()
        self.name = name
        self.oldVersion = oldVersion
        self.newVersion = newVersion
    }
}

struct UpdateResult: Codable {
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

    func updateAll(greedy: Bool = false, onProgress: (@Sendable (String) -> Void)? = nil) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        // Run brew update
        _ = try await runCommand(brewPath, arguments: ["update"])

        // Run brew upgrade with streaming output for progress
        var upgradeArgs = ["upgrade"]
        if greedy {
            upgradeArgs.append("--greedy")
        }
        let upgradeOutput: String
        if let onProgress {
            upgradeOutput = try await runCommandStreaming(brewPath, arguments: upgradeArgs, onLine: onProgress)
        } else {
            upgradeOutput = try await runCommand(brewPath, arguments: upgradeArgs)
        }

        // Parse the upgrade output to find upgraded packages
        let packages = parseUpgradeOutput(upgradeOutput)
        return UpdateResult(packages: packages, timestamp: Date())
    }

    private func parseUpgradeOutput(_ output: String) -> [UpgradedPackage] {
        var packages: [UpgradedPackage] = []
        var capturedNames = Set<String>()  // Track captured packages to avoid duplicates

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Pattern 1: "package 1.0 -> 2.0" or "==> Upgrading package 1.0 -> 2.0"
            // This captures version transitions from summary lines and upgrade messages
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

                        if !capturedNames.contains(name) {
                            capturedNames.insert(name)
                            packages.append(UpgradedPackage(
                                name: name,
                                oldVersion: oldVersion,
                                newVersion: newVersion
                            ))
                        }
                    }
                }
            }
            // Pattern 2: "==> Upgrading <name>" for casks that don't show version transition
            // This catches cask upgrades that only show the package name being upgraded
            else if line.hasPrefix("==> Upgrading ") {
                let afterPrefix = line.replacingOccurrences(of: "==> Upgrading ", with: "")
                                      .trimmingCharacters(in: .whitespaces)

                // Skip summary lines like "1 outdated package:" or "2 outdated packages:"
                if afterPrefix.contains("outdated package") { continue }

                // Extract package name (first component, handles "chatgpt" or "google-chrome")
                let components = afterPrefix.components(separatedBy: .whitespaces)
                let name = components.first ?? ""

                if !name.isEmpty && !capturedNames.contains(name) {
                    capturedNames.insert(name)
                    // Use "?" for versions when not available in this format
                    packages.append(UpgradedPackage(
                        name: name,
                        oldVersion: "?",
                        newVersion: "?"
                    ))
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

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: BrewError.commandFailed(output))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runCommandStreaming(_ command: String, arguments: [String], onLine: @escaping @Sendable (String) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let outputData = NSMutableData()

            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "")
            process.environment = environment

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                outputData.append(data)
                if let text = String(data: data, encoding: .utf8) {
                    let lines = text.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        onLine(line)
                    }
                }
            }

            process.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
                if !remainingData.isEmpty {
                    outputData.append(remainingData)
                }

                let output = String(data: outputData as Data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: BrewError.commandFailed(output))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Permission Error Detection

    func isPermissionError(_ output: String) -> Bool {
        let keywords = [
            "Permission denied",
            "Operation not permitted",
            "Failure while executing",
            "password is required",
            "requires root",
            "sudo",
            "insufficient permissions"
        ]
        let lowercased = output.lowercased()
        return keywords.contains { lowercased.contains($0.lowercased()) }
    }

    // MARK: - Admin Privilege Execution

    private func runCommandWithAdmin(_ command: String, arguments: [String]) async throws -> String {
        let fullCommand = ([command] + arguments)
            .map { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "'\\''") }
            .joined(separator: " ")

        let appleScript = "do shell script \"\(fullCommand)\" with administrator privileges"

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]
            process.standardOutput = pipe
            process.standardError = errorPipe

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    // User cancelled the password dialog
                    if errorOutput.contains("User canceled") || errorOutput.contains("user canceled") {
                        continuation.resume(throwing: BrewError.commandFailed("Admin authentication cancelled by user."))
                    } else {
                        continuation.resume(throwing: BrewError.commandFailed(errorOutput.isEmpty ? output : errorOutput))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func updateAllWithAdmin(greedy: Bool = false, onProgress: (@Sendable (String) -> Void)? = nil) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        var upgradeArgs = ["upgrade"]
        if greedy {
            upgradeArgs.append("--greedy")
        }

        let upgradeOutput = try await runCommandWithAdmin(brewPath, arguments: upgradeArgs)

        if let onProgress {
            let lines = upgradeOutput.components(separatedBy: .newlines)
            for line in lines where !line.isEmpty {
                onProgress(line)
            }
        }

        let packages = parseUpgradeOutput(upgradeOutput)
        return UpdateResult(packages: packages, timestamp: Date())
    }

    func upgradePackageWithAdmin(_ name: String) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        let upgradeOutput = try await runCommandWithAdmin(brewPath, arguments: ["upgrade", name])
        let packages = parseUpgradeOutput(upgradeOutput)
        return UpdateResult(packages: packages, timestamp: Date())
    }
}
