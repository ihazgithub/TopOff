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

@MainActor
class BrewService: ObservableObject {
    @Published var isRunning = false
    @Published var lastOutput: String = ""

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

    func updateAll(greedy: Bool = false) async throws -> String {
        guard let brewPath = brewPath else {
            throw BrewError.brewNotFound
        }

        isRunning = true
        defer { isRunning = false }

        // Run brew update
        let updateOutput = try await runCommand(brewPath, arguments: ["update"])

        // Run brew upgrade
        var upgradeArgs = ["upgrade"]
        if greedy {
            upgradeArgs.append("--greedy")
        }
        let upgradeOutput = try await runCommand(brewPath, arguments: upgradeArgs)

        let fullOutput = updateOutput + "\n" + upgradeOutput
        lastOutput = fullOutput
        return fullOutput
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
