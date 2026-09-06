import Foundation
import Darwin

@main struct ProviderCheck {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/provider-check-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw NSError(domain: "ProviderCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            print("PASS: \(message)")
        }
        func makeFixture(_ name: String, _ body: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }

        func waitGone(_ pid: pid_t, timeout: TimeInterval = 2) throws {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if kill(pid, 0) == -1 && errno == ESRCH { return }
                Thread.sleep(forTimeInterval: 0.02)
            }
            try expect(kill(pid, 0) == -1 && errno == ESRCH, "process \(pid) is no longer running")
        }

        let argsFile = root.appendingPathComponent("args.txt")
        let envFile = root.appendingPathComponent("env.txt")
        let shapeFixture = try makeFixture("shape.sh", "printf '%s\\n' \"$@\" > '\(argsFile.path)'; env | sort > '\(envFile.path)'; exit 0")
        _ = try CacheProvider.uv.run(at: root, executable: shapeFixture, timeout: 2)
        let args = try String(contentsOf: argsFile, encoding: .utf8)
        let env = try String(contentsOf: envFile, encoding: .utf8)
        try expect(args.contains("cache\n") && args.contains("--cache-dir\n\(root.path)\n") && args.contains("--no-config\n"), "provider arguments are passed with deterministic shape")
        try expect(env.contains("HOME=\(NSHomeDirectory())\n") && env.contains("PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin\n") && env.contains("PIP_CONFIG_FILE=/dev/null\n"), "provider environment is passed with deterministic shape")

        let heldPIDFile = root.appendingPathComponent("held.pid")
        let heldPipe = try makeFixture("held-pipe.sh", "(sleep 5) & echo $! > '\(heldPIDFile.path)'; exit 0")
        let start = Date()
        let output = try CacheProvider.uv.run(at: root, executable: heldPipe, timeout: 2)
        try expect(output.contains("completed"), "parent success returns despite child retaining output pipe")
        try expect(Date().timeIntervalSince(start) < 1, "held output pipe does not delay completion")
        if let pidText = try? String(contentsOf: heldPIDFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), let pid = pid_t(pidText) {
            try waitGone(pid)
        } else {
            throw NSError(domain: "ProviderCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "held-pipe fixture did not report child pid"])
        }

        let childPIDFile = root.appendingPathComponent("child.pid")
        let timeoutFixture = try makeFixture("timeout.sh", "(trap '' TERM; while :; do printf x; done) & echo $! > '\(childPIDFile.path)'; trap '' TERM; while :; do printf x; done")
        let timeoutStart = Date()
        do {
            _ = try CacheProvider.uv.run(at: root, executable: timeoutFixture, timeout: 1)
            throw NSError(domain: "ProviderCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "timeout fixture unexpectedly succeeded"])
        } catch let error as StorageError {
            try expect(error.localizedDescription.contains("timed out"), "timeout reports provider timeout")
        }
        try expect(Date().timeIntervalSince(timeoutStart) < 4, "timeout terminates the whole process group within the bound")
        if let pidText = try? String(contentsOf: childPIDFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), let childPID = pid_t(pidText) {
            try waitGone(childPID)
            print("PASS: timeout leaves no provider descendant running")
        } else {
            throw NSError(domain: "ProviderCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "timeout fixture did not report child pid"])
        }
    }
}
