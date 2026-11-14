import Darwin
import Foundation

/// Hands the admin password to sudo without writing it to disk.
///
/// TopOff points `SUDO_ASKPASS` at a small script that connects to a Unix
/// socket this server listens on and prints whatever comes back. The password
/// lives only in this object's memory. Before answering, the server asks the
/// kernel which process connected (`LOCAL_PEERPID`) and refuses unless that
/// process was started by `/usr/bin/sudo` running inside the brew process
/// TopOff launched. Anything else that runs the script, or connects to the
/// socket directly, gets nothing and the script exits 1.
///
/// The socket and script live in a fresh 0700 directory under the per-user
/// temporary directory, removed by `stop()`. Leftovers from a crash hold no
/// password and are swept at launch by `removeStaleFiles()`.
final class AskpassServer: @unchecked Sendable {
    /// Prefix for every file and directory TopOff's admin path creates in the
    /// temporary directory, current and legacy.
    static let filePrefix = "topoff-askpass-"

    let scriptPath: String

    private let directoryPath: String
    private let socketPath: String
    private let isAuthorized: @Sendable (pid_t) -> Bool
    private let queue = DispatchQueue(label: "com.topoff.askpass")
    private let lock = NSLock()
    private var password: [UInt8]
    private var source: DispatchSourceRead?

    /// - Parameter isAuthorized: decides, from the connecting process's PID,
    ///   whether to hand over the password. Production callers pass
    ///   `isSudoInsideProcess(_:rootPID:)`; tests can pass a stub.
    init(password: String, isAuthorized: @escaping @Sendable (pid_t) -> Bool) throws {
        self.password = Array(password.utf8) + [UInt8(ascii: "\n")]
        self.isAuthorized = isAuthorized

        // mkdtemp creates the directory with mode 0700. Unix socket paths are
        // capped at 104 bytes; the per-user temporary directory keeps this
        // well under (about 90).
        var template = Array((NSTemporaryDirectory() + Self.filePrefix + "XXXXXX").utf8CString)
        guard let created = mkdtemp(&template) else {
            throw Self.posixError("mkdtemp failed")
        }
        directoryPath = String(cString: created)
        socketPath = directoryPath + "/s"
        scriptPath = directoryPath + "/askpass"

        do {
            try startListening()
            try Self.writeScript(toPath: scriptPath, socketPath: socketPath)
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
    }

    /// Stop answering, wipe the password from memory, and remove the socket
    /// and script. Safe to call more than once.
    func stop() {
        lock.lock()
        let source = self.source
        self.source = nil
        for index in password.indices { password[index] = 0 }
        password = []
        lock.unlock()

        source?.cancel()
        try? FileManager.default.removeItem(atPath: directoryPath)
    }

    private func startListening() throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Self.posixError("socket failed") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw Self.posixError("socket path too long: \(socketPath)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            throw Self.posixError("bind/listen failed at \(socketPath)")
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPending(on: fd)
        }
        source.setCancelHandler {
            close(fd)
        }
        lock.lock()
        self.source = source
        lock.unlock()
        source.resume()
    }

    private func acceptPending(on listenFD: Int32) {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }   // EAGAIN: nothing left to accept
            answer(client)
            close(client)
        }
    }

    private func answer(_ client: Int32) {
        var noSigPipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var peer: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &peer, &length) == 0,
              peer > 0,
              isAuthorized(peer) else {
            return   // closing without a reply makes the script exit 1
        }

        lock.lock()
        let reply = password
        lock.unlock()
        guard !reply.isEmpty else { return }

        var copy = reply
        copy.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(client, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
        for index in copy.indices { copy[index] = 0 }
    }

    // MARK: - Askpass script

    /// Write the script sudo runs as its askpass program. It asks the server
    /// for the password and prints it; an empty reply (refused, or TopOff no
    /// longer listening) exits 1 so sudo treats it as a cancelled prompt.
    /// stdin comes from /dev/null so `nc` returns as soon as the server closes
    /// the connection, whatever stdin sudo hands it.
    static func writeScript(toPath scriptPath: String, socketPath: String) throws {
        let script = """
        #!/bin/sh
        PASSWORD=$(/usr/bin/nc -U \(shellSingleQuoteEscape(socketPath)) </dev/null) || exit 1
        [ -n "$PASSWORD" ] || exit 1
        printf '%s\\n' "$PASSWORD"
        """
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptPath
        )
    }

    /// Wrap `value` in single quotes for safe interpolation into a shell
    /// command. Any embedded `'` is escaped using the canonical
    /// `'\''` (close, literal apostrophe, reopen) pattern.
    static func shellSingleQuoteEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Who may ask

    /// True when `peer` descends from `/usr/bin/sudo` (the askpass script and
    /// its `nc` are sudo's children or grandchildren), and that sudo in turn
    /// descends from `rootPID`, the brew process TopOff launched. Process
    /// lookups are injectable for tests.
    static func isSudoInsideProcess(
        _ peer: pid_t,
        rootPID: pid_t?,
        parent: (pid_t) -> pid_t? = processParent,
        path: (pid_t) -> String? = processPath
    ) -> Bool {
        guard let rootPID, rootPID > 1 else { return false }

        // Find the nearest sudo above the peer: askpass script, maybe a
        // command-substitution subshell, then sudo.
        var current = peer
        var sudoPID: pid_t?
        for _ in 0..<4 {
            guard let next = parent(current), next > 1 else { return false }
            if path(next) == "/usr/bin/sudo" {
                sudoPID = next
                break
            }
            current = next
        }
        guard var current = sudoPID else { return false }

        // That sudo must be running inside TopOff's brew process.
        for _ in 0..<64 {
            guard let next = parent(current), next > 1 else { return false }
            if next == rootPID { return true }
            current = next
        }
        return false
    }

    static func processParent(_ pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    static func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Leftovers

    /// Remove askpass leftovers from earlier runs that ended without cleaning
    /// up (crash, force quit). The password and script files versions before
    /// 2.2.2 wrote are always removed. This server's directories hold no
    /// password, so they're only removed once they're an hour old, which
    /// leaves a run in progress in another copy of TopOff (say, a Debug build
    /// next to the installed app) alone.
    static func removeStaleFiles(in directory: String = NSTemporaryDirectory(), now: Date = Date()) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return }
        for name in names {
            let path = (directory as NSString).appendingPathComponent(name)
            let isLegacy = name.hasPrefix("topoff-pw-")
                || (name.hasPrefix(filePrefix) && name.hasSuffix(".sh"))
            if isLegacy {
                try? fileManager.removeItem(atPath: path)
                continue
            }
            guard name.hasPrefix(filePrefix),
                  let modified = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) > 60 * 60 else {
                continue
            }
            try? fileManager.removeItem(atPath: path)
        }
    }

    private static func posixError(_ message: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
