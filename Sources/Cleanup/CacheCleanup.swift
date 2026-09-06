import Foundation
import Darwin

enum CacheProvider: String, Sendable {
    case uv, pip

    static func matching(_ url: URL) -> CacheProvider? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if [".cache/uv", "Library/Caches/uv"].contains(where: { home.appendingPathComponent($0).path == url.standardizedFileURL.path }) { return .uv }
        if home.appendingPathComponent("Library/Caches/pip").path == url.standardizedFileURL.path { return .pip }
        return nil
    }

    var executable: URL? {
        let paths = self == .uv
            ? ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", NSHomeDirectory() + "/.local/bin/uv"]
            : ["/opt/homebrew/bin/pip3", "/usr/local/bin/pip3", "/usr/bin/pip3"]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
    }

    var action: String { self == .uv ? "Prune unused uv cache" : "Clear pip download cache" }
    var consequence: String {
        self == .uv
            ? "Permanently removes unused cache entries and centralized project environments. uv recreates environments when needed. Active installs are protected by uv’s lock. The amount removable is determined by uv."
            : "Permanently clears cached downloads and wheels, keeping installed packages. Future installs may download or rebuild them. Finish any pip installations before continuing."
    }

    func validate(_ item: Candidate) throws {
        guard item.kind == .cache, item.selectable, Self.matching(item.url) == self,
              item.root == item.url.deletingLastPathComponent(), Storage.noLinkAncestry(item.url),
              let root = try? Identity.read(item.root), root.device == item.rootIdentity.device, root.inode == item.rootIdentity.inode,
              let current = try? Identity.read(item.url), current.isDirectory,
              current.device == item.identity.device, current.inode == item.identity.inode else {
            throw StorageError.message("Cache location changed or is not supported. Scan and review again.")
        }
        guard executable != nil else { throw StorageError.message("\(rawValue) is unavailable. Install or repair it outside Yeoback, then scan again.") }
    }

    func clean(_ item: Candidate) throws -> String {
        try validate(item)
        guard let executable else { throw StorageError.message("Cleanup tool is unavailable.") }
        return try run(at: item.url, executable: executable)
    }

    // Fixture checks exercise this runner; UI execution always uses validated clean(_:).
    func run(at root: URL, executable: URL, timeout: TimeInterval = 90) throws -> String {
        let arguments = self == .uv
            ? ["cache", "prune", "--cache-dir", root.path, "--offline", "--no-config", "--no-progress", "--color", "never", "--no-python-downloads"]
            : ["--isolated", "--disable-pip-version-check", "--no-input", "--cache-dir", root.path, "cache", "purge"]
        let environment = ["HOME=\(NSHomeDirectory())", "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "LANG=en_US.UTF-8", "UV_LOCK_TIMEOUT=5", "PIP_CONFIG_FILE=/dev/null"]
        var outputPipe = [Int32](repeating: 0, count: 2)
        guard pipe(&outputPipe) == 0 else { throw StorageError.message("Could not create provider output pipe.") }
        defer { if outputPipe[0] >= 0 { close(outputPipe[0]) }; if outputPipe[1] >= 0 { close(outputPipe[1]) } }

        var actions: posix_spawn_file_actions_t? = nil
        var attributes: posix_spawnattr_t? = nil
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            throw StorageError.message("Could not initialize provider process actions.")
        }
        guard posix_spawnattr_init(&attributes) == 0 else {
            posix_spawn_file_actions_destroy(&actions)
            throw StorageError.message("Could not initialize provider process attributes.")
        }
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        guard posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDERR_FILENO) == 0,
              posix_spawn_file_actions_addclose(&actions, outputPipe[0]) == 0,
              posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, "/") == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            throw StorageError.message("Could not configure provider process actions.")
        }

        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer {
            argv.forEach { if let value = $0 { free(value) } }
            envp.forEach { if let value = $0 { free(value) } }
        }
        var pid: pid_t = 0
        let spawnResult = argv.withUnsafeBufferPointer { argvBuffer in
            envp.withUnsafeBufferPointer { envBuffer in
                posix_spawn(&pid, executable.path, &actions, &attributes, argvBuffer.baseAddress, envBuffer.baseAddress)
            }
        }
        guard spawnResult == 0 else { throw StorageError.message("Could not start \(rawValue): \(String(cString: strerror(spawnResult))).") }
        close(outputPipe[1])
        outputPipe[1] = -1
        var status: Int32 = 0
        func forceKillAndReap() throws {
            let killResult = kill(-pid, SIGKILL)
            guard killResult == 0 || errno == ESRCH else { throw StorageError.message("Could not force-stop \(rawValue): \(String(cString: strerror(errno))).") }
            let waited = waitpid(pid, &status, 0)
            guard waited == pid || (waited == -1 && errno == ECHILD) else {
                throw StorageError.message("Could not reap \(rawValue) after stopping it.")
            }
        }
        let flags = fcntl(outputPipe[0], F_GETFL, 0)
        guard flags >= 0, fcntl(outputPipe[0], F_SETFL, flags | O_NONBLOCK) == 0 else {
            try forceKillAndReap()
            throw StorageError.message("Could not configure provider output handling.")
        }

        let capture = BoundedOutput()
        var exited = false
        let deadline = Date().addingTimeInterval(max(0, timeout))
        func drainOutput(maxBytes: Int) -> Bool {
            var buffer = [UInt8](repeating: 0, count: 1024)
            var drained = 0
            while drained < maxBytes {
                let count = buffer.withUnsafeMutableBytes { read(outputPipe[0], $0.baseAddress, $0.count) }
                if count > 0 { capture.append(Data(buffer.prefix(Int(count)))); drained += Int(count) }
                else if count == -1 && errno == EINTR { continue }
                else if count == 0 { return true }
                else { break }
            }
            return false
        }
        while !exited {
            _ = drainOutput(maxBytes: 64 * 1024)
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { exited = true; break }
            if result == -1 {
                if errno == EINTR { continue }
                let waitError = errno
                try forceKillAndReap()
                throw StorageError.message("Could not wait for \(rawValue) to finish: \(String(cString: strerror(waitError))).")
            }
            if Date() >= deadline { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let timedOut = !exited
        func terminateGroup(parentReaped: Bool, graceInterval: TimeInterval) throws {
            let termResult = kill(-pid, SIGTERM)
            guard termResult == 0 || errno == ESRCH else { throw StorageError.message("Could not stop \(rawValue): \(String(cString: strerror(errno))).") }
            let grace = Date().addingTimeInterval(graceInterval)
            var reaped = parentReaped
            while !reaped && Date() < grace {
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid { reaped = true; break }
                if result == -1 {
                    if errno == EINTR { continue }
                    if errno == ECHILD { reaped = true; break }
                    throw StorageError.message("Could not wait for \(rawValue) to stop: \(String(cString: strerror(errno))).")
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            if Date() < grace { Thread.sleep(forTimeInterval: grace.timeIntervalSinceNow) }
            let killResult = kill(-pid, SIGKILL)
            guard killResult == 0 || errno == ESRCH else { throw StorageError.message("Could not force-stop \(rawValue): \(String(cString: strerror(errno))).") }
            if !reaped {
                let waited = waitpid(pid, &status, 0)
                guard waited == pid || (waited == -1 && errno == ECHILD) else {
                    throw StorageError.message("Could not reap \(rawValue) after stopping it.")
                }
            }
        }
        try terminateGroup(parentReaped: exited, graceInterval: timedOut ? 2 : 0.1)
        let drainDeadline = Date().addingTimeInterval(1)
        while Date() < drainDeadline {
            if drainOutput(maxBytes: 64 * 1024) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let output = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let exitCode = (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
        guard !timedOut, exitCode == 0 else {
            throw StorageError.message("\(rawValue) \(timedOut ? "timed out" : "exited with code \(exitCode)"). Some entries may already have been removed. Scan again. \(output)")
        }
        return "\(action) completed. \(output.isEmpty ? "Provider returned success." : output)"
    }
}

private final class BoundedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk.prefix(max(0, 8_192 - data.count)))
    }
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
