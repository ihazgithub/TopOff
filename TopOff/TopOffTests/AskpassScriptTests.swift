import XCTest
@testable import TopOff

final class AskpassScriptTests: XCTestCase {

    private var scratchDir: URL!

    override func setUp() {
        super.setUp()
        scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("topoff-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratchDir)
        super.tearDown()
    }

    /// Runs the askpass script the way sudo would and returns its exit
    /// status, stdout, and PID.
    private func runScript(_ scriptPath: String) throws -> (status: Int32, output: String, pid: pid_t) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptPath, "Password:"]
        process.standardOutput = pipe
        try process.run()
        let pid = process.processIdentifier
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output, pid)
    }

    // MARK: - Server and script

    func testScriptPrintsPasswordWhenAuthorized() throws {
        let server = try AskpassServer(password: "hunter2 with spaces") { _ in true }
        defer { server.stop() }

        let result = try runScript(server.scriptPath)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "hunter2 with spaces\n")
    }

    func testScriptPrintsNothingAndFailsWhenRefused() throws {
        let server = try AskpassServer(password: "hunter2") { _ in false }
        defer { server.stop() }

        let result = try runScript(server.scriptPath)
        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(result.output, "")
    }

    func testServerSeesTheProcessThatConnected() throws {
        // Look the lineage up while the peer is still connected.
        let seen = PeerLog()
        let server = try AskpassServer(password: "hunter2") { peer in
            seen.record(path: AskpassServer.processPath(peer), lineage: Self.ancestors(of: peer, levels: 3))
            return false
        }
        defer { server.stop() }

        let result = try runScript(server.scriptPath)
        let entry = try XCTUnwrap(seen.entries.first)

        // The peer is nc, started by the script (possibly through a
        // command-substitution subshell).
        XCTAssertEqual(entry.path, "/usr/bin/nc")
        XCTAssertTrue(entry.lineage.contains(result.pid), "script \(result.pid) not in \(entry.lineage)")
    }

    private static func ancestors(of pid: pid_t, levels: Int) -> [pid_t] {
        var result: [pid_t] = []
        var current = pid
        for _ in 0..<levels {
            guard let parent = AskpassServer.processParent(current), parent > 0 else { break }
            result.append(parent)
            current = parent
        }
        return result
    }

    func testPasswordIsNeverWrittenToDisk() throws {
        let server = try AskpassServer(password: "correct-horse-battery") { _ in true }
        defer { server.stop() }

        let directory = (server.scriptPath as NSString).deletingLastPathComponent
        let names = try FileManager.default.contentsOfDirectory(atPath: directory)
        XCTAssertEqual(Set(names), ["askpass", "s"])

        let script = try String(contentsOfFile: server.scriptPath, encoding: .utf8)
        XCTAssertFalse(script.contains("correct-horse-battery"))
    }

    func testDirectoryIsPrivateAndRemovedOnStop() throws {
        let server = try AskpassServer(password: "hunter2") { _ in true }
        let directory = (server.scriptPath as NSString).deletingLastPathComponent

        let attributes = try FileManager.default.attributesOfItem(atPath: directory)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory))
    }

    func testScriptEscapesSocketPath() throws {
        let scriptPath = scratchDir.appendingPathComponent("askpass").path
        try AskpassServer.writeScript(toPath: scriptPath, socketPath: "/tmp/it's here/s")
        let script = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertTrue(script.contains(#"'/tmp/it'\''s here/s'"#))
    }

    // MARK: - Who may ask

    /// nc (100) ← sh (99) ← sudo (98) ← ruby/brew (97, TopOff's process).
    private let parents: [pid_t: pid_t] = [100: 99, 99: 98, 98: 97, 97: 50, 50: 1]
    private let paths: [pid_t: String] = [
        100: "/usr/bin/nc", 99: "/bin/bash", 98: "/usr/bin/sudo",
        97: "/opt/homebrew/Library/Homebrew/vendor/portable-ruby/current/bin/ruby",
        50: "/Applications/TopOff.app/Contents/MacOS/TopOff"
    ]

    private func authorized(_ peer: pid_t, root: pid_t?,
                            parents: [pid_t: pid_t]? = nil,
                            paths: [pid_t: String]? = nil) -> Bool {
        let parentTable = parents ?? self.parents
        let pathTable = paths ?? self.paths
        return AskpassServer.isSudoInsideProcess(
            peer,
            rootPID: root,
            parent: { parentTable[$0] },
            path: { pathTable[$0] }
        )
    }

    func testSudoInsideBrewIsAuthorized() {
        XCTAssertTrue(authorized(100, root: 97))
    }

    func testNoBrewRunningIsRefused() {
        XCTAssertFalse(authorized(100, root: nil))
    }

    func testRunningTheScriptDirectlyIsRefused() {
        // A process that read SUDO_ASKPASS and ran it: no sudo above nc.
        let parents: [pid_t: pid_t] = [100: 99, 99: 97, 97: 50, 50: 1]
        XCTAssertFalse(authorized(100, root: 97, parents: parents))
    }

    func testSudoOutsideBrewIsRefused() {
        // Someone else's `sudo -A`, not started by TopOff's brew.
        let parents: [pid_t: pid_t] = [100: 99, 99: 98, 98: 60, 60: 1]
        XCTAssertFalse(authorized(100, root: 97, parents: parents))
    }

    func testSudoTooFarAboveIsRefused() {
        let parents: [pid_t: pid_t] = [100: 101, 101: 102, 102: 103, 103: 104, 104: 98, 98: 97, 97: 1]
        XCTAssertFalse(authorized(100, root: 97, parents: parents))
    }

    // MARK: - Admin retry scope

    func testAdminRetryOnlyCoversRequestedCasksStillOutdated() {
        let output = """
        ==> Auto-updating Homebrew...
        docker-desktop
        musescore
        wispr-flow
        """
        XCTAssertEqual(
            BrewService.namesNeedingAdminRetry(
                requested: ["libffi", "wispr-flow", "docker-desktop", "claude"],
                outdatedCasksOutput: output
            ),
            ["wispr-flow", "docker-desktop"]
        )
    }

    func testAdminUpgradesRunOneCaskPerProcess() {
        XCTAssertEqual(
            BrewService.adminUpgradeArgumentBatches(caskNames: ["a", "b"]),
            [["upgrade", "--cask", "--greedy", "a"], ["upgrade", "--cask", "--greedy", "b"]]
        )
    }

    // MARK: - Leftovers

    func testRemoveStaleFiles() throws {
        let fileManager = FileManager.default
        let dir = scratchDir.path
        func path(_ name: String) -> String { (dir as NSString).appendingPathComponent(name) }

        fileManager.createFile(atPath: path("topoff-pw-1234.txt"), contents: Data("secret".utf8))
        fileManager.createFile(atPath: path("topoff-askpass-1234.sh"), contents: Data())
        try fileManager.createDirectory(atPath: path("topoff-askpass-fresh1"), withIntermediateDirectories: false)
        try fileManager.createDirectory(atPath: path("topoff-askpass-old123"), withIntermediateDirectories: false)
        try fileManager.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-2 * 60 * 60)],
            ofItemAtPath: path("topoff-askpass-old123")
        )
        fileManager.createFile(atPath: path("unrelated.txt"), contents: Data())

        AskpassServer.removeStaleFiles(in: dir)

        XCTAssertEqual(
            Set(try fileManager.contentsOfDirectory(atPath: dir)),
            ["topoff-askpass-fresh1", "unrelated.txt"]
        )
    }
}

private final class PeerLog: @unchecked Sendable {
    struct Entry {
        let path: String?
        let lineage: [pid_t]
    }

    private let lock = NSLock()
    private var recorded: [Entry] = []

    func record(path: String?, lineage: [pid_t]) {
        lock.lock()
        recorded.append(Entry(path: path, lineage: lineage))
        lock.unlock()
    }

    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
