import Foundation

enum BrewError: Error, LocalizedError {
    case brewNotFound
    case permissionDenied(String)
    case commandFailed(String)

    case networkUnavailable(String)
    case diskFull(String)
    case commandLineToolsRequired(String)
    case brewBusy(String)
    case caskUnavailable(packageName: String?, output: String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Homebrew not installed"
        case .permissionDenied:
            return "Administrator access needed"
        case .commandFailed:
            return "Homebrew couldn't complete the update"
        case .networkUnavailable:
            return "Network connection issue"
        case .diskFull:
            return "Disk is full"
        case .commandLineToolsRequired:
            return "Command Line Tools are missing"
        case .brewBusy:
            return "Homebrew is busy"
        case .caskUnavailable(let name, _):
            return "\(name ?? "A package") is no longer available"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .brewNotFound:
            return "Install Homebrew from brew.sh first."
        case .permissionDenied:
            return "Some packages need admin privileges. Try again — you'll be asked for your password."
        case .commandFailed:
            return "Run brew doctor in Terminal for a diagnosis."
        case .networkUnavailable:
            return "Check your internet and try again. If it persists, check System Settings → Network."
        case .diskFull:
            return "Free up space and try again. Run brew cleanup --prune=all from the Cleanup menu to reclaim cache."
        case .commandLineToolsRequired:
            return "Open Terminal and run xcode-select --install, then retry."
        case .brewBusy:
            return "Another Homebrew operation is running. Wait a moment and try again."
        case .caskUnavailable:
            return "Homebrew has removed it. Skip it from the menu to stop seeing it as outdated."
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

    var hasKnownNewVersion: Bool {
        newVersion != "?" && !newVersion.isEmpty
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

    /// Repairs records produced by the pre-fix upgrade parser. Older builds
    /// could bake a package's old version and column padding into the `name`
    /// field (leaving `oldVersion` empty) and emit a duplicate `?`/`?` entry
    /// for the same package. This trims names back to the real package name,
    /// recovers the leaked old version, and collapses duplicates by name —
    /// keeping whichever entry carries real version info. It's idempotent, so
    /// clean records pass through unchanged.
    func sanitized() -> UpdateResult {
        var cleaned: [UpgradedPackage] = []
        var indexByName: [String: Int] = [:]

        for package in packages {
            // A real package name never contains whitespace. If one does, the
            // first token is the name and any second token is the old version
            // that leaked in from the column-aligned summary line.
            let tokens = package.name
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
            let cleanName = tokens.first ?? package.name.trimmingCharacters(in: .whitespaces)
            guard !cleanName.isEmpty else { continue }

            var oldVersion = package.oldVersion
            if oldVersion.isEmpty, tokens.count >= 2 {
                oldVersion = tokens[1]
            }
            let candidate = UpgradedPackage(
                name: cleanName,
                oldVersion: oldVersion,
                newVersion: package.newVersion
            )

            if let existing = indexByName[cleanName] {
                // Same package listed twice — prefer the entry with real
                // version info over a "?"/"" placeholder.
                if !cleaned[existing].hasKnownNewVersion && candidate.hasKnownNewVersion {
                    cleaned[existing] = candidate
                }
            } else {
                indexByName[cleanName] = cleaned.count
                cleaned.append(candidate)
            }
        }

        return UpdateResult(packages: cleaned, timestamp: timestamp)
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

enum AutoCleanupStyle: String, CaseIterable, Identifiable {
    case standard
    case deepPruneAll

    static let userDefaultsKey = "autoCleanupStyle"

    var id: String { rawValue }

    var deepPruneAll: Bool {
        self == .deepPruneAll
    }

    static func stored(in defaults: UserDefaults = .standard) -> AutoCleanupStyle {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let style = AutoCleanupStyle(rawValue: rawValue) else {
            return .standard
        }

        return style
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }
}

@MainActor
final class BrewService: @unchecked Sendable {
    // Safe: the only instance property `brewPath` is a `let`, set once in init.
    // All other state lives inside individual method calls. Marking Sendable
    // lets us spawn detached Tasks that capture `self` so the brew subprocess
    // can start spawning on a background thread while NSAlert blocks main.
    let brewPath: String?

    init() {
        self.brewPath = Self.findBrewPath()
    }

    static func findBrewPath() -> String? {
        #if DEBUG
        // Demo/testing hook: lets a debug build talk to a stand-in brew
        // (see gitignored demo/fakebrew.sh) for marketing captures and
        // UI testing. Compiled out of Release builds entirely.
        if let override = ProcessInfo.processInfo.environment["TOPOFF_BREW_PATH"],
           FileManager.default.fileExists(atPath: override) {
            return override
        }
        #endif

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
        packages: [OutdatedPackage],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        // Run brew update
        _ = try await runCommand(brewPath, arguments: ["update"])

        guard !packages.isEmpty else {
            return UpdateResult(packages: [], timestamp: Date())
        }

        // Run regular upgrades first, then include greedy casks when requested.
        let names = packages.map(\.name)
        var upgradeOutputs: [String] = []
        for upgradeArgs in Self.upgradeArgumentBatches(greedy: greedy, packageNames: names) {
            let output: String
            if let onProgress {
                output = try await runCommandStreaming(brewPath, arguments: upgradeArgs, onLine: onProgress)
            } else {
                output = try await runCommand(brewPath, arguments: upgradeArgs)
            }
            upgradeOutputs.append(output)
        }

        let combined = upgradeOutputs.joined(separator: "\n")
        let upgraded = Self.fillingUnknownVersions(Self.parseUpgradeOutput(combined), from: packages)
        return UpdateResult(
            packages: try await appendingReinstalledRefusedCasks(
                to: upgraded,
                output: combined,
                candidates: packages,
                useAdmin: false,
                onProgress: onProgress
            ),
            timestamp: Date()
        )
    }

    /// Homebrew refuses to `brew upgrade` some casks in place — typically
    /// `auto_updates` apps that updated themselves, leaving the on-disk app out
    /// of sync with Homebrew's records — printing:
    ///   Warning: The cask 'NAME' cannot be upgraded as-is. To fix this, run:
    ///   brew reinstall --cask --force NAME
    /// Returns the distinct cask names that need a forced reinstall instead.
    nonisolated static func casksNeedingReinstall(from output: String) -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            guard line.contains("cannot be upgraded as-is"),
                  let open = line.range(of: "The cask '"),
                  let close = line.range(of: "'", range: open.upperBound..<line.endIndex) else {
                continue
            }
            let name = String(line[open.upperBound..<close.lowerBound])
            if !name.isEmpty && seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
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

    /// The requested packages that `brew outdated --cask --quiet` still
    /// lists, in the order requested. Lines that aren't a requested name
    /// (auto-update hints and the like) are ignored.
    nonisolated static func namesNeedingAdminRetry(requested: [String], outdatedCasksOutput: String) -> [String] {
        let outdated = Set(
            outdatedCasksOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        )
        return requested.filter { outdated.contains($0) }
    }

    /// One `brew upgrade` per cask, so `SUDO_ASKPASS` only ever reaches the
    /// cask being upgraded. `--greedy` matches the per-row Update: a named
    /// `auto_updates` cask is otherwise skipped as "nothing to do".
    nonisolated static func adminUpgradeArgumentBatches(caskNames: [String]) -> [[String]] {
        caskNames.map { ["upgrade", "--cask", "--greedy", $0] }
    }

    static func parseUpgradeOutput(_ output: String) -> [UpgradedPackage] {
        var packages: [UpgradedPackage] = []
        var indexByName: [String: Int] = [:]  // Track captured packages to avoid duplicates
        var isReadingUpgradeSummary = false
        // Package named by the most recent "==> Upgrading <name>" header.
        // Newer Homebrew prints that header first and the versions on the
        // next line ("  1.0 -> 2.0"), so the versions are attributed back to it.
        var currentUpgradingName: String?

        // Adds a package, or fills in versions for one captured earlier with
        // "?" placeholders.
        func capture(_ package: UpgradedPackage) {
            if let index = indexByName[package.name] {
                if !packages[index].hasKnownNewVersion && package.hasKnownNewVersion {
                    packages[index] = package
                }
            } else {
                indexByName[package.name] = packages.count
                packages.append(package)
            }
        }

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
               let package = parseGreedyCaskSummaryLine(trimmedLine) {
                capture(package)
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
                    // Split on whitespace *runs*, not a single space. Newer
                    // Homebrew column-aligns the upgrade summary, padding the
                    // name/old-version columns with multiple spaces so the
                    // arrows line up. A single-space split turned that padding
                    // into empty components, which baked the old version into
                    // the name (leaving oldVersion empty) and — because the
                    // malformed name dodged the dedup guard — spawned a
                    // duplicate "?"/"?" entry from the later "==> Upgrading"
                    // line.
                    let leftParts = parts[0]
                        .split(whereSeparator: { $0 == " " || $0 == "\t" })
                        .map(String.init)
                    let newVersion = parts[1].trimmingCharacters(in: .whitespaces)
                    if leftParts.count >= 2 {
                        let name = leftParts.dropLast().joined(separator: " ")
                        let oldVersion = leftParts.last ?? ""
                        capture(UpgradedPackage(
                            name: name,
                            oldVersion: oldVersion,
                            newVersion: newVersion
                        ))
                    } else if leftParts.count == 1,
                              let name = currentUpgradingName {
                        // Indented "  1.0 -> 2.0" line under "==> Upgrading <name>".
                        // Drop trailing install options ("1.0 -> 2.0 --HEAD").
                        let version = newVersion
                            .split(whereSeparator: { $0 == " " || $0 == "\t" })
                            .first
                            .map(String.init) ?? newVersion
                        capture(UpgradedPackage(
                            name: name,
                            oldVersion: leftParts[0],
                            newVersion: version
                        ))
                    }
                }
            }
            // Pattern 2: "==> Upgrading <name>" for casks that don't show version transition
            // This catches cask upgrades that only show the package name being upgraded
            else if line.hasPrefix("==> Upgrading ") {
                let afterPrefix = line.replacingOccurrences(of: "==> Upgrading ", with: "")
                                      .trimmingCharacters(in: .whitespaces)

                // Skip summary lines like "1 outdated package:" or
                // "2 dependents of upgraded formulae:"
                if afterPrefix.contains("outdated package") || afterPrefix.hasSuffix(":") { continue }

                // Extract package name (first component, handles "chatgpt" or "google-chrome")
                let components = afterPrefix.components(separatedBy: .whitespaces)
                let name = components.first ?? ""

                if !name.isEmpty {
                    currentUpgradingName = name
                    // Use "?" for versions when not available in this format;
                    // a following "  old -> new" line fills them in.
                    capture(UpgradedPackage(
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

    func upgradePackage(_ package: OutdatedPackage) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        // Always pass `--greedy` for an explicit per-package upgrade. Casks
        // marked `auto_updates true` (e.g. omnissa-horizon-client) are
        // invisible to a plain `brew upgrade <name>` — brew says "nothing
        // to do" because greedy casks are assumed to self-update. Per-row
        // Update is an explicit user intent to upgrade *this* thing, so
        // honor that even when TopOff's global Greedy mode is off. For
        // formulae and non-auto_updates casks `--greedy` is a no-op.
        let upgradeOutput = try await runCommand(brewPath, arguments: ["upgrade", "--greedy", package.name])
        let upgraded = Self.fillingUnknownVersions(Self.parseUpgradeOutput(upgradeOutput), from: [package])
        return UpdateResult(
            packages: try await appendingReinstalledRefusedCasks(
                to: upgraded,
                output: upgradeOutput,
                candidates: [package],
                useAdmin: false,
                onProgress: nil
            ),
            timestamp: Date()
        )
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

    /// Force-reinstalls casks Homebrew won't upgrade in place (see
    /// `casksNeedingReinstall`). Runs `brew reinstall --cask --force <name>`
    /// for each and reports the version change from the outdated metadata.
    func reinstallCasks(
        _ packages: [OutdatedPackage],
        useAdmin: Bool = false,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }
        guard !packages.isEmpty else {
            return UpdateResult(packages: [], timestamp: Date())
        }

        var reinstalled: [UpgradedPackage] = []
        for package in packages {
            // Emit an Upgrading line so the progress UI tracks the reinstall.
            onProgress?("==> Upgrading \(package.name)")
            _ = try await runCommandStreamingIfNeeded(
                brewPath,
                arguments: ["reinstall", "--cask", "--force", package.name],
                useAdmin: useAdmin,
                onProgress: onProgress
            )
            reinstalled.append(UpgradedPackage(
                name: package.name,
                oldVersion: package.currentVersion,
                newVersion: package.latestVersion
            ))
        }

        return UpdateResult(packages: reinstalled, timestamp: Date())
    }

    /// Replaces "?" placeholder versions with the versions `brew outdated`
    /// reported before the upgrade, for output that never printed them.
    nonisolated static func fillingUnknownVersions(
        _ packages: [UpgradedPackage],
        from candidates: [OutdatedPackage]
    ) -> [UpgradedPackage] {
        let candidatesByName = Dictionary(candidates.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return packages.map { package in
            guard !package.hasKnownNewVersion, let candidate = candidatesByName[package.name] else {
                return package
            }
            return UpgradedPackage(
                name: package.name,
                oldVersion: candidate.currentVersion,
                newVersion: candidate.latestVersion
            )
        }
    }

    /// After an upgrade attempt, reinstall any casks Homebrew refused ("cannot
    /// be upgraded as-is") among `candidates`, appending the results to
    /// `packages` (deduped by name).
    private func appendingReinstalledRefusedCasks(
        to packages: [UpgradedPackage],
        output: String,
        candidates: [OutdatedPackage],
        useAdmin: Bool,
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> [UpgradedPackage] {
        let refusedNames = Set(Self.casksNeedingReinstall(from: output))
        let refused = candidates.filter { refusedNames.contains($0.name) }
        guard !refused.isEmpty else { return packages }

        let reinstalled = try await reinstallCasks(refused, useAdmin: useAdmin, onProgress: onProgress)
        var result = packages
        var names = Set(packages.map(\.name))
        for package in reinstalled.packages where names.insert(package.name).inserted {
            result.append(package)
        }
        return result
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

    static func cleanupArguments(deepPruneAll: Bool) -> [String] {
        deepPruneAll ? ["cleanup", "--prune=all"] : ["cleanup"]
    }

    func cleanup(deepPruneAll: Bool = false) async throws -> CleanupResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        let output = try await runCommand(
            brewPath,
            arguments: Self.cleanupArguments(deepPruneAll: deepPruneAll)
        )
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

    /// Run a command and return its combined stdout/stderr output.
    ///
    /// Implemented on top of `runCommandStreaming` (with a no-op line
    /// callback) so output is drained from the pipe as it is produced.
    /// Reading only after termination deadlocks once the subprocess emits
    /// more than the kernel's ~64 KB pipe buffer: the subprocess blocks
    /// writing to the full pipe and never exits, so the termination
    /// handler never fires — `brew update` easily exceeds that after a
    /// few weeks of formula churn.
    nonisolated private func runCommand(
        _ command: String,
        arguments: [String],
        extraEnvironment: [String: String] = [:],
        onProcess: (@Sendable (Process) -> Void)? = nil
    ) async throws -> String {
        try await runCommandStreaming(
            command,
            arguments: arguments,
            extraEnvironment: extraEnvironment,
            onProcess: onProcess,
            onLine: { _ in }
        )
    }

    /// Lock-guarded byte buffer shared between `readabilityHandler` and
    /// `terminationHandler`, which fire on different queues. `NSMutableData`
    /// is not thread-safe, so appends are serialized behind an `NSLock`.
    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            data.append(chunk)
        }

        var snapshot: Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    nonisolated private func runCommandStreaming(
        _ command: String,
        arguments: [String],
        extraEnvironment: [String: String] = [:],
        onProcess: (@Sendable (Process) -> Void)? = nil,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let outputBuffer = OutputBuffer()

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
                outputBuffer.append(data)
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
                    outputBuffer.append(remainingData)
                }

                let output = String(data: outputBuffer.snapshot, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: BrewError.commandFailed(output))
                }
            }

            do {
                try process.run()
                onProcess?(process)
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
            return try await runCommandWithAdmin(
                command,
                arguments: arguments,
                packageName: nil,
                onLine: onProgress
            )
        }

        if let onProgress {
            return try await runCommandStreaming(command, arguments: arguments, onLine: onProgress)
        }

        return try await runCommand(command, arguments: arguments)
    }

    // MARK: - Admin Privilege Execution

    /// Run one or more brew invocations under a single admin password
    /// prompt. The password is requested once (per attempt) and reused across
    /// every batch, so greedy mode or several casks don't each ask for it.
    ///
    /// The password never touches the disk. `AskpassServer` holds it in
    /// memory and hands it only to sudo running inside the brew process
    /// currently in flight; the script `SUDO_ASKPASS` points at prints
    /// nothing for anyone else.
    ///
    /// On a wrong password only the failing batch is retried (up to
    /// `maxAttempts` prompts total); batches that already completed are
    /// never re-run. A batch that fails for any other reason doesn't stop
    /// the rest; the failures are thrown together at the end.
    private func runCommandsWithAdmin(
        _ command: String,
        argumentBatches: [[String]],
        packageName: String? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> [String] {
        let maxAttempts = 3
        var attempt = 0
        var errorMessageForRetry: String? = nil
        var outputs: [String] = []
        var failures: [String] = []
        var batchIndex = 0

        while attempt < maxAttempts {
            attempt += 1

            // Prompt first, then spawn brew. Running brew while the prompt
            // is up blocked the main actor, and brew asks sudo several times
            // per cask install (preflight, install, postflight), so the
            // password has to stay available for the whole batch.
            let prompt = await AdminPasswordPromptWindowController.present(
                forPackage: packageName,
                errorMessage: errorMessageForRetry
            )

            let password: String
            switch prompt {
            case .cancelled:
                throw BrewError.commandFailed("Admin authentication cancelled by user.")
            case .submitted(let p):
                password = p
            }

            let processHolder = ProcessHolder()
            let askpass = try AskpassServer(password: password) { peer in
                AskpassServer.isSudoInsideProcess(peer, rootPID: processHolder.processIdentifier)
            }
            defer { askpass.stop() }

            // Watcher: if we see sudo's "Sorry, try again" or similar
            // auth-failure output, kill brew immediately so the retry kicks
            // in fast. If the watcher misses the marker (brew might swallow
            // sudo's stderr), we still fall back to brew's natural exit —
            // sudo's 3-retry limit ensures brew exits with auth output.
            let env = ["SUDO_ASKPASS": askpass.scriptPath]
            let userOnLine = onLine
            let watchedOnLine: @Sendable (String) -> Void = { line in
                if Self.isAuthFailure(line) {
                    processHolder.terminate()
                }
                userOnLine?(line)
            }

            do {
                // Run every remaining batch under this one password prompt.
                // `batchIndex` lives outside the attempt loop, so batches
                // that completed before a wrong-password failure are not
                // re-run on the next attempt.
                while batchIndex < argumentBatches.count {
                    do {
                        let output = try await runCommandStreaming(
                            command,
                            arguments: argumentBatches[batchIndex],
                            extraEnvironment: env,
                            onProcess: { processHolder.set($0) },
                            onLine: watchedOnLine
                        )
                        outputs.append(output)
                    } catch let BrewError.commandFailed(output) where !Self.isAuthFailure(output) {
                        failures.append(output)
                    }
                    batchIndex += 1
                }
                if !failures.isEmpty {
                    throw BrewError.commandFailed(failures.joined(separator: "\n"))
                }
                return outputs
            } catch let BrewError.commandFailed(output) where Self.isAuthFailure(output) && attempt < maxAttempts {
                errorMessageForRetry = "Incorrect password — please try again."
                continue
            } catch let BrewError.commandFailed(output) where Self.isAuthFailure(output) {
                throw BrewError.commandFailed("Authentication failed after \(maxAttempts) attempts. Cancelled.")
            }
            // Non-auth errors propagate via the `runCommandStreaming` throw above
        }

        // Should be unreachable due to throws in the loop
        throw BrewError.commandFailed("Admin retry loop exhausted.")
    }

    /// Single-invocation convenience over `runCommandsWithAdmin`.
    private func runCommandWithAdmin(
        _ command: String,
        arguments: [String],
        packageName: String? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let outputs = try await runCommandsWithAdmin(
            command,
            argumentBatches: [arguments],
            packageName: packageName,
            onLine: onLine
        )
        return outputs.first ?? ""
    }

    func updateAllWithAdmin(
        greedy: Bool = false,
        packages: [OutdatedPackage],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        guard !packages.isEmpty else {
            return UpdateResult(packages: [], timestamp: Date())
        }

        // This runs after a normal update hit a permission error, so
        // everything that could update without admin rights already has.
        // Only casks can need the password (Homebrew refuses to run formulae
        // as root), so retry just the casks still outdated, one brew process
        // each. The password is then only reachable from the cask that needs
        // it, never from formulae or other casks in the same run.
        var outdatedCaskArgs = ["outdated", "--cask", "--quiet"]
        if greedy {
            outdatedCaskArgs.append("--greedy")
        }
        let outdatedCasks = try await runCommand(brewPath, arguments: outdatedCaskArgs)
        let caskNames = Self.namesNeedingAdminRetry(requested: packages.map(\.name), outdatedCasksOutput: outdatedCasks)
        guard !caskNames.isEmpty else {
            throw BrewError.commandFailed("Some packages couldn't be updated, and none of them are apps that need administrator access.")
        }

        // One admin prompt covers every cask in the list.
        let upgradeOutputs = try await runCommandsWithAdmin(
            brewPath,
            argumentBatches: Self.adminUpgradeArgumentBatches(caskNames: caskNames),
            packageName: caskNames.count == 1 ? caskNames[0] : nil,
            onLine: onProgress
        )

        let combined = upgradeOutputs.joined(separator: "\n")
        let retried = packages.filter { caskNames.contains($0.name) }
        let upgraded = Self.fillingUnknownVersions(Self.parseUpgradeOutput(combined), from: retried)
        return UpdateResult(
            packages: try await appendingReinstalledRefusedCasks(
                to: upgraded,
                output: combined,
                candidates: retried,
                useAdmin: true,
                onProgress: onProgress
            ),
            timestamp: Date()
        )
    }

    func upgradePackageWithAdmin(_ package: OutdatedPackage) async throws -> UpdateResult {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        // See `upgradePackage` for why `--greedy` is unconditional here.
        let upgradeOutput = try await runCommandWithAdmin(
            brewPath,
            arguments: ["upgrade", "--greedy", package.name],
            packageName: package.name
        )
        let upgraded = Self.fillingUnknownVersions(Self.parseUpgradeOutput(upgradeOutput), from: [package])
        return UpdateResult(
            packages: try await appendingReinstalledRefusedCasks(
                to: upgraded,
                output: upgradeOutput,
                candidates: [package],
                useAdmin: true,
                onProgress: nil
            ),
            timestamp: Date()
        )
    }

    // MARK: - Admin helpers

    /// Thread-safe holder for a running Process. The `runCommand` /
    /// `runCommandStreaming` callbacks invoke `set` from the background Task's
    /// continuation closure; `runCommandWithAdmin` calls `terminate` from the
    /// main actor on user cancel. Both sides synchronize through the lock.
    private final class ProcessHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?

        func set(_ process: Process) {
            lock.lock()
            self.process = process
            lock.unlock()
        }

        /// PID of the brew process currently running, if any. The askpass
        /// server only answers sudo running inside this process.
        var processIdentifier: pid_t? {
            lock.lock()
            let p = process
            lock.unlock()
            guard let p, p.isRunning else { return nil }
            return p.processIdentifier
        }

        /// Send SIGKILL to the process and its process group. SIGTERM
        /// (`Process.terminate()`) is not sufficient — brew's Ruby runtime
        /// catches SIGTERM and keeps running cleanup work. The negative pid
        /// addresses the entire process group, which kills brew plus any
        /// `sudo` / `installer` children it spawned.
        func terminate() {
            lock.lock()
            let p = process
            lock.unlock()
            guard let p, p.isRunning else { return }
            let pid = p.processIdentifier
            kill(-pid, SIGKILL)   // group
            kill(pid, SIGKILL)    // process itself, in case it isn't a group leader
        }
    }

    /// Detect sudo's "wrong password" output patterns. Used by the admin retry
    /// loop to decide whether to re-prompt vs. surface the error. Nonisolated
    /// because it's a pure string check called from the background `runTask`
    /// (Task.detached) on every output line.
    nonisolated static func isAuthFailure(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("sorry, try again")
            || lower.contains("incorrect password")
            || lower.contains("authentication failure")
            || lower.contains("authentication failed")
    }
}
