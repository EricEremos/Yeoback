import SwiftUI
import AppKit

@main struct CleanupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @StateObject private var growth: GrowthModel
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("showMenuBar") private var showMenuBar = true
    private static let applicationLock = ApplicationLock()

    init() {
        if CommandLine.arguments.contains("--self-check") {
            let result = SelfCheck.run()
            exit(result ? 0 : 1)
        }
        if CommandLine.arguments.contains("--help") {
            print("Yeoback: native macOS storage review and folder growth tracking. Open Yeoback.app, or run --self-check for disposable-fixture verification. No unattended cleanup mode.")
            exit(0)
        }
        do {
            let lockURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cleanup/application.lock")
            guard try Self.applicationLock.acquire(at: lockURL) else {
                NSRunningApplication.runningApplications(withBundleIdentifier: "dev.blueock.cleanup")
                    .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?.activate()
                exit(0)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Yeoback could not start safely"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            exit(1)
        }
        _model = StateObject(wrappedValue: AppModel())
        _growth = StateObject(wrappedValue: GrowthModel())
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Yeoback", id: "main") {
            ContentView().environmentObject(model).environmentObject(growth)
                .onAppear { appDelegate.model = model }
                .frame(minWidth: 920, minHeight: 660)
                .tint(Palette.controlAccent)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        }
        .defaultSize(width: 1120, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandMenu("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            CommandGroup(after: .newItem) {
                Button("Choose Folder to Scan…") { model.chooseFolder() }.keyboardShortcut("o")
                    .disabled(model.busy || model.removing)
                Button("Refresh Capacity") { model.refresh() }.keyboardShortcut("r")
                Button("Review and Clean…") { model.prepareReview() }.keyboardShortcut("k")
                    .disabled(model.selection.isEmpty || model.busy || model.removing)
                Button("Select All Visible Results") { model.selectVisible(true) }.keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!model.isInventory || model.busy || model.removing || model.visibleItems.isEmpty)
            }
        }
        MenuBarExtra("Yeoback", systemImage: "internaldrive", isInserted: $showMenuBar) {
            MenuPanel().environmentObject(model)
        }
    }
}

struct MenuPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        if let capacity = model.capacity {
            Text("\(sizeText(capacity.free)) available")
        }
        Text("\(model.monitorLabel) · \(Int(model.state.targetGB)) GB target")
        Text(model.state.monitoring ? "Checks every minute while running" : "Monitoring paused")
        Divider()
        Button("Open Yeoback") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Refresh Capacity") { model.refresh() }
        Divider()
        Button("Quit Yeoback") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
