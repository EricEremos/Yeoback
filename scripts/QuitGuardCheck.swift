import AppKit

@main struct QuitGuardCheck {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/quit-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(stateURL: root.appendingPathComponent("state.json"))
        let delegate = AppDelegate()
        delegate.model = model
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        model.removing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            app.activate(ignoringOtherApps: true)
            app.terminate(nil)
            print("PASS: Native Quit returned without terminating during simulated cleanup")
            model.removing = false
            guard delegate.applicationShouldTerminate(app) == .terminateNow else { fatalError("Idle Quit refused") }
            print("PASS: Quit becomes available after cleanup finishes")
            app.stop(nil)
            app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
        app.run()
    }
}
