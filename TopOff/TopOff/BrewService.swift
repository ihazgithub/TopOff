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

struct OutdatedPackage: Identifiable, Codable, Equatable {
    var id: String { name }
    var hasInterruptedCaskUpgrade: Bool { currentVersion.contains(".upgrading") }

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

    func supplemented(with progressItems: [UpdateProgressItem]) -> UpdateResult {
        var packages = packages
        var capturedNames = Set(packages.map(\.name))

        for item in progressItems where item.state == .finished && !capturedNames.contains(item.name) {
            capturedNames.insert(item.name)
            packages.append(UpgradedPackage(
                name: item.name,
                oldVersion: item.currentVersion,
                newVersion: item.latestVersion
            ))
        }

        return UpdateResult(packages: packages, timestamp: timestamp)
    }

    func excludingPackagesStillOutdated(_ outdatedPackages: [OutdatedPackage]) -> UpdateResult {
        let outdatedNames = Set(outdatedPackages.map(\.name))
        return UpdateResult(
            packages: packages.filter { !outdatedNames.contains($0.name) },
            timestamp: timestamp
        )
    }
}

struct UpdateProgressItem: Identifiable, Equatable {
    enum State {
        case queued
        case updating
        case repairing
        case attempted
        case finished
    }

    let id = UUID()
    let name: String
    let currentVersion: String
    let latestVersion: String
    var state: State
}

struct UpdateProgressSnapshot {
    let items: [UpdateProgressItem]

    var count: Int { items.count }
    var currentItem: UpdateProgressItem? {
        items.first { $0.state == .updating || $0.state == .repairing }
    }

    var title: String {
        guard !items.isEmpty else { return "Updating..." }

        if let currentItem {
            let index = (items.firstIndex { $0.name == currentItem.name } ?? 0) + 1
            let verb = currentItem.state == .repairing ? "Repairing" : "Updating"
            return "\(verb) \(index) of \(items.count): \(currentItem.name)"
        }

        return "Updating \(items.count) item\(items.count == 1 ? "" : "s")..."
    }
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

    func checkOutdated(greedy: Bool = false) async throws -> [OutdatedPackage] {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        // Run brew update first to refresh package info
        _ = try await runCommand(brewPath, arguments: ["update"])

        // Then check what's outdated with verbose output for version info
        var outdatedArgs = ["outdated", "--verbose"]
        if greedy {
            outdatedArgs.append("--greedy")
        }
        let output = try await runCommand(brewPath, arguments: outdatedArgs)
        return Self.parseOutdatedVerbose(output)
    }

    func updateAll(
        greedy: Bool = false,
        packageNames: [String]? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        // Run brew update
        _ = try await runCommand(brewPath, arguments: ["update"])

        if let packageNames, packageNames.isEmpty {
            return UpdateResult(packages: [], timestamp: Date())
        }

        // Run regular upgrades first, then include greedy casks when requested.
        var upgradeOutputs: [String] = []
        for upgradeArgs in Self.upgradeArgumentBatches(greedy: greedy, packageNames: packageNames) {
            let output: String
            if let onProgress {
                output = try await runCommandStreaming(brewPath, arguments: upgradeArgs, onLine: onProgress)
            } else {
                output = try await runCommand(brewPath, arguments: upgradeArgs)
            }
            upgradeOutputs.append(output)
        }

        // Parse the upgrade output to find upgraded packages
        let packages = Self.parseUpgradeOutput(upgradeOutputs.joined(separator: "\n"))
        return UpdateResult(packages: packages, timestamp: Date())
    }

    static func upgradeArgumentBatches(greedy: Bool, packageNames: [String]? = nil) -> [[String]] {
        let names = packageNames ?? []
        if greedy {
            return [
                ["upgrade"] + names,
                ["upgrade", "--greedy"] + names
            ]
        }

        return [["upgrade"] + names]
    }

    static func parseUpgradeOutput(_ output: String) -> [UpgradedPackage] {
        var packages: [UpgradedPackage] = []
        var capturedNames = Set<String>()  // Track captured packages to avoid duplicates
        var isReadingUpgradeSummary = false

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("==> Upgrading "),
               trimmedLine.contains("outdated package") {
                isReadingUpgradeSummary = true
                continue
            } else if trimmedLine.hasPrefix("==> ") {
                isReadingUpgradeSummary = false
            }

            if isReadingUpgradeSummary,
               let package = parseGreedyCaskSummaryLine(trimmedLine),
               !capturedNames.contains(package.name) {
                capturedNames.insert(package.name)
                packages.append(package)
                continue
            }

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

    nonisolated static func upgradingPackageName(from line: String) -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix("==> Upgrading ") else { return nil }

        let afterPrefix = trimmedLine.replacingOccurrences(of: "==> Upgrading ", with: "")
            .trimmingCharacters(in: .whitespaces)

        if afterPrefix.contains("outdated package") { return nil }

        return afterPrefix.components(separatedBy: .whitespaces).first
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    nonisolated static func repairingPackageName(from line: String) -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix("==> Repairing ") else { return nil }

        let afterPrefix = trimmedLine.replacingOccurrences(of: "==> Repairing ", with: "")
            .trimmingCharacters(in: .whitespaces)

        return afterPrefix.components(separatedBy: .whitespaces).first
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func parseGreedyCaskSummaryLine(_ line: String) -> UpgradedPackage? {
        guard !line.isEmpty else { return nil }

        let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard components.count == 2 else { return nil }

        let versions = components[1].split(separator: ",", maxSplits: 1).map(String.init)
        guard versions.count == 2 else { return nil }

        return UpgradedPackage(
            name: components[0],
            oldVersion: versions[0],
            newVersion: versions[1]
        )
    }

    nonisolated static func parseOutdatedVerbose(_ output: String) -> [OutdatedPackage] {
        // brew outdated --verbose outputs lines like:
        // node (20.1.0) < 22.0.0
        // python@3.12 (3.11.4) < 3.12.1
        // google-chrome (146.0.7680.80) != 148.0.7778.168
        var packages: [OutdatedPackage] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let separator: String
            if trimmed.contains(" < ") {
                separator = " < "
            } else if trimmed.contains(" != ") {
                separator = " != "
            } else {
                continue
            }

            let parts = trimmed.components(separatedBy: separator)
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
        let packages = Self.parseUpgradeOutput(upgradeOutput)
        return UpdateResult(packages: packages, timestamp: Date())
    }

    func repairInterruptedCaskUpgrades(
        _ packages: [OutdatedPackage],
        useAdmin: Bool = false,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        let interruptedPackages = packages.filter(\.hasInterruptedCaskUpgrade)
        guard !interruptedPackages.isEmpty else {
            return UpdateResult(packages: [], timestamp: Date())
        }

        let prefix = try await runCommand(brewPath, arguments: ["--prefix"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var repairedPackages: [UpgradedPackage] = []
        for package in interruptedPackages {
            onProgress?("==> Repairing \(package.name)")
            _ = try Self.moveStaleCaskUpgradeBackups(
                packageName: package.name,
                homebrewPrefix: prefix
            )

            do {
                _ = try await runCommandStreamingIfNeeded(
                    brewPath,
                    arguments: ["install", "--cask", "--adopt", package.name],
                    useAdmin: useAdmin,
                    onProgress: onProgress
                )
            } catch {
                _ = try await runCommandStreamingIfNeeded(
                    brewPath,
                    arguments: ["install", "--cask", "--force", package.name],
                    useAdmin: useAdmin,
                    onProgress: onProgress
                )
            }

            repairedPackages.append(UpgradedPackage(
                name: package.name,
                oldVersion: package.currentVersion.replacingOccurrences(of: ".upgrading", with: ""),
                newVersion: package.latestVersion
            ))
        }

        return UpdateResult(packages: repairedPackages, timestamp: Date())
    }

    nonisolated static func staleCaskUpgradeBackupPaths(
        packageName: String,
        homebrewPrefix: String,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let caskroomURL = URL(fileURLWithPath: homebrewPrefix)
            .appendingPathComponent("Caskroom")
            .appendingPathComponent(packageName)
        let metadataURL = caskroomURL.appendingPathComponent(".metadata")
        var urls: [URL] = []

        if let versionURLs = try? fileManager.contentsOfDirectory(
            at: caskroomURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            urls.append(contentsOf: versionURLs.filter { $0.lastPathComponent.hasSuffix(".upgrading") })
        }

        if let metadataURLs = try? fileManager.contentsOfDirectory(
            at: metadataURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            urls.append(contentsOf: metadataURLs.filter { $0.lastPathComponent.hasSuffix(".upgrading") })
        }

        return urls
    }

    @discardableResult
    nonisolated static func moveStaleCaskUpgradeBackups(
        packageName: String,
        homebrewPrefix: String,
        recoveryRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/TopOff/CaskRecovery"),
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let paths = try staleCaskUpgradeBackupPaths(
            packageName: packageName,
            homebrewPrefix: homebrewPrefix,
            fileManager: fileManager
        )
        guard !paths.isEmpty else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let recoveryURL = recoveryRoot
            .appendingPathComponent("\(formatter.string(from: Date()))-\(sanitizedPackageName(packageName))")
        try fileManager.createDirectory(at: recoveryURL, withIntermediateDirectories: true)

        var movedURLs: [URL] = []
        for path in paths {
            let destinationName: String
            if path.deletingLastPathComponent().lastPathComponent == ".metadata" {
                destinationName = "metadata-\(path.lastPathComponent)"
            } else {
                destinationName = path.lastPathComponent
            }

            var destination = recoveryURL.appendingPathComponent(destinationName)
            var suffix = 1
            while fileManager.fileExists(atPath: destination.path) {
                suffix += 1
                destination = recoveryURL.appendingPathComponent("\(destinationName)-\(suffix)")
            }

            try fileManager.moveItem(at: path, to: destination)
            movedURLs.append(destination)
        }

        return movedURLs
    }

    nonisolated private static func sanitizedPackageName(_ packageName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = packageName.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars)
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

    private func runCommand(_ command: String, arguments: [String], extraEnvironment: [String: String] = [:]) async throws -> String {
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
            environment.merge(extraEnvironment) { _, new in new }
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

    private func runCommandStreaming(
        _ command: String,
        arguments: [String],
        extraEnvironment: [String: String] = [:],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> String {
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
            environment.merge(extraEnvironment) { _, new in new }
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

    private func runCommandStreamingIfNeeded(
        _ command: String,
        arguments: [String],
        useAdmin: Bool = false,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        if useAdmin {
            return try await runCommandWithAdmin(command, arguments: arguments, onLine: onProgress)
        }

        if let onProgress {
            return try await runCommandStreaming(command, arguments: arguments, onLine: onProgress)
        }

        return try await runCommand(command, arguments: arguments)
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

    private func createAskpassScript() throws -> String {
        let script = """
        #!/bin/sh
        PROMPT="$1"
        if [ -z "$PROMPT" ]; then
          PROMPT="Administrator access is required to continue."
        fi

        PASSWORD=$(/usr/bin/osascript - "$PROMPT" <<'APPLESCRIPT'
        on run argv
            set promptText to "Password:"
            if (count of argv) > 0 then
                set promptText to item 1 of argv
            end if
            try
                display dialog promptText with title "TopOff" default answer "" buttons {"Cancel", "OK"} default button "OK" with hidden answer
                return text returned of result
            on error number -128
                error "User canceled" number 1
            end try
        end run
        APPLESCRIPT
        )

        if [ $? -ne 0 ]; then
          exit 1
        fi

        printf '%s\\n' "$PASSWORD"
        """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("topoff-askpass-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }

    private func runCommandWithAdmin(
        _ command: String,
        arguments: [String],
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let askpassPath = try createAskpassScript()
        defer { try? FileManager.default.removeItem(atPath: askpassPath) }

        let environment = [
            "SUDO_ASKPASS": askpassPath
        ]

        do {
            if let onLine {
                return try await runCommandStreaming(
                    command,
                    arguments: arguments,
                    extraEnvironment: environment,
                    onLine: onLine
                )
            } else {
                return try await runCommand(
                    command,
                    arguments: arguments,
                    extraEnvironment: environment
                )
            }
        } catch BrewError.commandFailed(let output) {
            let lowercased = output.lowercased()
            if lowercased.contains("user canceled") ||
               lowercased.contains("user cancelled") ||
               lowercased.contains("no password was provided") {
                throw BrewError.commandFailed("Admin authentication cancelled by user.")
            }
            throw BrewError.commandFailed(output)
        }
    }

    func updateAllWithAdmin(
        greedy: Bool = false,
        packageNames: [String]? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        if let packageNames, packageNames.isEmpty {
            return UpdateResult(packages: [], timestamp: Date())
        }

        var upgradeOutputs: [String] = []
        for upgradeArgs in Self.upgradeArgumentBatches(greedy: greedy, packageNames: packageNames) {
            let output = try await runCommandWithAdmin(
                brewPath,
                arguments: upgradeArgs,
                onLine: onProgress
            )
            upgradeOutputs.append(output)
        }

        let packages = Self.parseUpgradeOutput(upgradeOutputs.joined(separator: "\n"))
        return UpdateResult(packages: packages, timestamp: Date())
    }

    func upgradePackageWithAdmin(_ name: String) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        let upgradeOutput = try await runCommandWithAdmin(brewPath, arguments: ["upgrade", name])
        let packages = Self.parseUpgradeOutput(upgradeOutput)
        return UpdateResult(packages: packages, timestamp: Date())
    }
}
