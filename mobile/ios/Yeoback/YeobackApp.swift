import SwiftUI
import UniformTypeIdentifiers

@main
struct YeobackApp: App {
    var body: some Scene { WindowGroup { FolderScreen() } }
}

enum Palette {
    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let muted = Color("Muted")
    static let accent = Color("Accent")
    static let surface = Color("Surface")
}

@MainActor
final class FolderModel: ObservableObject {
    @Published var inventory: FolderInventory?
    @Published var filter = FolderFilter()
    @Published var selected: Set<String> = []
    @Published var kept: Set<String> = []
    @Published var busy = false
    @Published var deleting = false
    @Published var progress = ""
    @Published var problem: String?
    @Published var outcomes: [RemovalOutcome] = []
    private var cancellation = ScanCancellation()
    private var scopedRoot: URL?
    var matching: [FolderItem] { inventory.map { filter.apply($0, kept: kept) } ?? [] }
    var selectedItems: [FolderItem] { inventory?.items.filter { selected.contains($0.id) } ?? [] }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    func open(_ root: URL, fixture: Bool = false) {
        guard !busy else { return }
        if let scopedRoot { scopedRoot.stopAccessingSecurityScopedResource() }
        scopedRoot = nil
        if !fixture {
            guard root.startAccessingSecurityScopedResource() else { problem = "Folder access was not granted. Choose the folder again."; return }
            scopedRoot = root
        }
        inventory = nil; selected = []; kept = []; outcomes = []; problem = nil
        cancellation = ScanCancellation()
        let token = cancellation
        busy = true; progress = "Inspecting folder metadata…"
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<FolderInventory, Error> in
                Result { try FolderEngine.scan(root: root, cancellation: token) { visited, found in
                    Task { @MainActor in self.progress = "\(visited) inspected · \(found) files found" }
                } }
            }.value
            busy = false
            switch result {
            case .success(let value): inventory = value
            case .failure(let error): problem = error.localizedDescription
            }
        }
    }

    func cancel() { cancellation.cancel() }
    func toggle(_ item: FolderItem) {
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }
    func selectMatching() { selected.formUnion(matching.map(\.id)) }
    func clearMatching() { selected.subtract(matching.map(\.id)) }
    func keep(_ item: FolderItem) { kept.insert(item.id); selected.remove(item.id) }
    func delete(_ reviewed: [FolderItem]) {
        guard !busy, let inventory, !reviewed.isEmpty else { return }
        busy = true; deleting = true; progress = "Rechecking reviewed files…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FolderEngine.remove(reviewed, inventory: inventory) { done, total in
                    Task { @MainActor in self.progress = "Processed \(done) of \(total) files" }
                }
            }.value
            outcomes = result
            let deletedIDs = Set(result.filter(\.deleted).map(\.id))
            self.inventory?.items.removeAll { deletedIDs.contains($0.id) }
            selected = []; busy = false; deleting = false
        }
    }

    #if DEBUG
    func prepareFixture() {
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("Yeoback-UI-\(UUID().uuidString)/Workbench", isDirectory: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("exports"), withIntermediateDirectories: true)
            for index in 1...15 {
                try Data(repeating: 65, count: index * 4096).write(to: root.appendingPathComponent("exports/draft-\(index).svg"))
            }
            try Data("Keep this original".utf8).write(to: root.appendingPathComponent("original.txt"))
            open(root, fixture: true)
        } catch { problem = error.localizedDescription }
    }
    #endif
}

struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(_ onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

func byteText(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }

struct FolderScreen: View {
    @StateObject private var model = FolderModel()
    @AppStorage("appearance") private var appearance = "System"
    @State private var picker = false
    @State private var filters = false
    @State private var review: ReviewSnapshot?
    @State private var showResults = false

    var body: some View {
        NavigationStack {
            List {
                if let inventory = model.inventory {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(inventory.root.lastPathComponent).font(.title2.weight(.semibold)).lineLimit(2).textSelection(.enabled)
                            Text("\(inventory.items.count) files · \(inventory.visited) entries inspected").font(.subheadline).foregroundStyle(Palette.muted)
                            Text(inventory.partial ? "Partial scan · some items were not inspected" : "Scan complete").font(.subheadline.weight(.medium))
                            if inventory.skipped > 0 { Text("\(inventory.skipped) skipped: unavailable, hidden, linked or unsupported entries may be excluded.").font(.footnote).foregroundStyle(Palette.muted) }
                            ForEach(inventory.issues, id: \.self) { Text($0).font(.footnote).foregroundStyle(Palette.muted) }
                        }.padding(.vertical, 2)
                    }
                    Section {
                        Picker("Show", selection: $model.filter.group) {
                            ForEach(ArtifactGroup.allCases) { Text($0.rawValue).tag($0) }
                        }.accessibilityIdentifier("category")
                        HStack {
                            Button("Select matching") { model.selectMatching() }.accessibilityIdentifier("select-matching")
                            Spacer()
                            Button("Clear") { model.selected = [] }.disabled(model.selected.isEmpty)
                        }.frame(minHeight: 44)
                        Text("\(model.matching.count) matching · \(model.selected.count) selected across filters")
                            .font(.footnote).foregroundStyle(Palette.muted).accessibilityIdentifier("selection-count")
                    } footer: {
                        Text("Filename clues only. AI origin and project usage are not verified. Review the files before deleting.")
                    }
                    if model.matching.isEmpty {
                        ContentUnavailableView("No matching files", systemImage: "line.3.horizontal.decrease.circle", description: Text("Change your filters or show all files. Kept items are hidden until you reset them."))
                    }
                    Section {
                        ForEach(model.matching) { item in
                            Button { model.toggle(item) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: model.selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(model.selected.contains(item.id) ? Palette.accent : Palette.muted)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.url.lastPathComponent).font(.body.weight(.medium)).foregroundStyle(Palette.ink)
                                        Text(item.relativePath).font(.caption).foregroundStyle(Palette.muted)
                                        if let clue = item.clue { Text(clue).font(.footnote).foregroundStyle(Palette.muted) }
                                        Text("\(byteText(item.bytes)) · \(item.modified.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
                                    }
                                }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .accessibilityLabel("\(item.relativePath), \(byteText(item.bytes)), \(model.selected.contains(item.id) ? "selected" : "not selected")")
                            .accessibilityIdentifier("file-\(item.url.lastPathComponent)")
                            .swipeActions { Button("Keep", systemImage: "bookmark") { model.keep(item) }.tint(.gray) }
                            .contextMenu { Button("Keep for this session", systemImage: "bookmark") { model.keep(item) } }
                        }
                    }
                } else if !model.busy {
                    Section {
                        VStack(alignment: .leading, spacing: 20) {
                            Image(systemName: "rectangle.inset.filled").font(.system(size: 40, weight: .light)).foregroundStyle(Palette.accent).accessibilityHidden(true)
                            Text("Room for what’s next.").font(.largeTitle.weight(.semibold))
                            Text("Find drafts, SVG exports and work records in a folder you choose.").font(.body).foregroundStyle(Palette.muted)
                            Button("Choose a folder", systemImage: "folder.badge.plus") { picker = true }
                                .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("choose-folder")
                            Text("Your files stay on your device. Yeoback can inspect only folders you grant access to, not other apps’ private data.")
                                .font(.footnote).foregroundStyle(Palette.muted)
                        }.padding(.vertical, 24)
                    }
                }
                if model.busy {
                    Section {
                        HStack { ProgressView(); Text(model.progress).font(.subheadline) }
                        if !model.deleting { Button("Stop scan") { model.cancel() } }
                    }
                }
                if let problem = model.problem {
                    Section("Couldn’t continue") { Text(problem); Button("Choose folder again") { picker = true } }
                }
                if !model.outcomes.isEmpty {
                    Section {
                        Button("View cleanup results") { showResults = true }.accessibilityIdentifier("view-results")
                    }
                }
            }
            .listSectionSpacing(16)
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollContentBackground(.hidden).background(Palette.paper)
            .listRowSeparatorTint(Color("Line"))
            .navigationTitle("Yeoback")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.filter.query, prompt: "Search filenames or folders")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Filters & sort", systemImage: "line.3.horizontal.decrease") { filters = true }
                        .accessibilityIdentifier("filters-sort")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Choose folder", systemImage: "folder") { picker = true }.disabled(model.busy)
                        Button("Filters & sort", systemImage: "line.3.horizontal.decrease") { filters = true }
                        if !model.kept.isEmpty { Button("Reset kept items (\(model.kept.count))") { model.kept = [] } }
                        Picker("Appearance", selection: $appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) } }
                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Options") }
                    .accessibilityIdentifier("options")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.inventory != nil {
                    VStack(spacing: 8) {
                        HStack { Text("\(model.selected.count) selected"); Spacer(); Text(byteText(model.selectedBytes)).monospacedDigit() }.font(.subheadline.weight(.medium))
                        Button("Review selected files") { review = ReviewSnapshot(items: model.selectedItems, folder: model.inventory?.root.lastPathComponent ?? "") }
                            .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                            .disabled(model.selected.isEmpty || model.busy).accessibilityIdentifier("review-selection")
                        Text("Selected file size · not measured free space").font(.caption).foregroundStyle(Palette.muted)
                    }.padding(16).background(Palette.surface)
                }
            }
            .sheet(isPresented: $picker) { FolderPicker { model.open($0); picker = false } }
            .sheet(isPresented: $filters) { filterSheet }
            .sheet(item: $review) { snapshot in ReviewScreen(snapshot: snapshot) { model.delete(snapshot.items); review = nil } }
            .sheet(isPresented: $showResults) { resultsSheet }
            .onChange(of: model.outcomes.count) { _, value in if value > 0 { showResults = true } }
        }
        .tint(Palette.accent).foregroundStyle(Palette.ink)
        .preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-fixture") { model.prepareFixture() }
            #endif
        }
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Picker("Minimum size", selection: $model.filter.minimumBytes) {
                    Text("Any size").tag(Int64(0)); Text("At least 1 MB").tag(Int64(1_000_000)); Text("At least 10 MB").tag(Int64(10_000_000)); Text("At least 100 MB").tag(Int64(100_000_000))
                }
                Picker("Modified", selection: $model.filter.olderThanDays) {
                    Text("Any time").tag(0); Text("Over 7 days ago").tag(7); Text("Over 30 days ago").tag(30); Text("Over 90 days ago").tag(90)
                }
                Picker("Order", selection: $model.filter.sort) { ForEach(FolderSort.allCases) { Text($0.rawValue).tag($0) } }
                Button("Reset filters") { model.filter = FolderFilter() }
            }.scrollContentBackground(.hidden).background(Palette.paper)
                .navigationTitle("Filters & sort").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { filters = false } } }
        }
    }

    private var resultsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(model.outcomes.filter(\.deleted).count) deleted · \(model.outcomes.filter { !$0.deleted }.count) kept").font(.title2.weight(.semibold)).accessibilityIdentifier("cleanup-summary")
                    Text("Deleted file size: \(byteText(model.outcomes.filter(\.deleted).reduce(0) { $0 + $1.logicalBytes }))").font(.subheadline)
                    Text("This is logical file size. Device free space may differ. Yeoback cannot undo this deletion.").font(.footnote).foregroundStyle(Palette.muted)
                }
                ForEach(model.outcomes) { outcome in
                    VStack(alignment: .leading, spacing: 6) { Text(outcome.name); Label(outcome.message, systemImage: outcome.deleted ? "checkmark.circle" : "exclamationmark.circle").font(.footnote) }
                }
            }.scrollContentBackground(.hidden).background(Palette.paper)
                .navigationTitle("Cleanup results").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showResults = false } } }
        }
    }
}

struct ReviewSnapshot: Identifiable {
    let id = UUID()
    let items: [FolderItem]
    let folder: String
}

struct ReviewScreen: View {
    let snapshot: ReviewSnapshot
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Make room, deliberately.").font(.title2.weight(.semibold))
                    Text("\(snapshot.items.count) files from \(snapshot.folder)").accessibilityIdentifier("review-count")
                    Text("\(byteText(snapshot.items.reduce(0) { $0 + $1.bytes })) selected file size").monospacedDigit()
                    Label("Permanent deletion", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(Palette.accent)
                    Text("Yeoback has no Trash or Undo for these files. Your provider may remove them permanently and sync that deletion to other devices. Check every file below.")
                    Text("Files that changed after scanning will be kept. Filename clues do not prove these files are unused.").font(.footnote).foregroundStyle(Palette.muted)
                }
                Section("Exact files to delete") {
                    ForEach(snapshot.items) { item in
                        VStack(alignment: .leading, spacing: 4) { Text(item.relativePath); Text(byteText(item.bytes)).font(.caption).foregroundStyle(Palette.muted) }
                    }
                }
                Section {
                    Button { acknowledged.toggle() } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: acknowledged ? "checkmark.square.fill" : "square").font(.title2)
                            Text("I understand this may permanently delete these files")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.foregroundStyle(Palette.ink).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(acknowledged ? "Acknowledged" : "Not acknowledged")
                    .accessibilityIdentifier("acknowledge-deletion")
                }
            }
            .scrollContentBackground(.hidden).background(Palette.paper)
            .navigationTitle("Review deletion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("cancel-review") } }
            .safeAreaInset(edge: .bottom) {
                Button("Delete \(snapshot.items.count) files", role: .destructive, action: onDelete)
                    .buttonStyle(.borderedProminent).tint(Palette.accent).controlSize(.large).padding().disabled(!acknowledged)
                    .accessibilityIdentifier("confirm-delete")
            }
        }.interactiveDismissDisabled(acknowledged)
    }
}
