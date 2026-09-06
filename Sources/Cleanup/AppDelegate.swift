import AppKit
import Darwin

final class ApplicationLock {
    private var descriptor: Int32 = -1
    func acquire(at url: URL) throws -> Bool {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw StorageError.message("Could not open the application lock.") }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
        let failure = errno
        close(descriptor)
        descriptor = -1
        guard failure == EWOULDBLOCK else { throw StorageError.message("Could not acquire the application lock.") }
        return false
    }
    deinit { if descriptor >= 0 { close(descriptor) } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.removing == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Cleanup is still running"
        alert.informativeText = "Use Stop after current batch in Activity, then wait for results to be saved before quitting."
        alert.addButton(withTitle: "Keep Yeoback Open")
        alert.runModal()
        return .terminateCancel
    }
}
