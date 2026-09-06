import SwiftUI
import AppKit

enum Palette {
    static let paper = adaptive(0xF5F3EF, 0x1D1F1E)
    static let ink = adaptive(0x252C27, 0xF1EEE8)
    static let muted = adaptive(0x62675F, 0xB8BDB4)
    static let line = adaptive(0xC5C9BF, 0x535D52)
    static let accent = adaptive(0xAE3529, 0xFF9988)
    static let tint = adaptive(0xE6E9E1, 0x353A35)
    static let surface = adaptive(0xFFFEFA, 0x252725)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

struct Rule: View { var body: some View { Rectangle().fill(Palette.line).frame(height: 1).accessibilityHidden(true) } }
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.3).foregroundStyle(Palette.muted) }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var growth: GrowthModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220).background(Palette.surface)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                if model.busy || model.removing { HStack {
                    if model.busy { ProgressView().controlSize(.small); Text("Scanning \(model.scanSection?.rawValue ?? "storage")").font(.caption); Button(model.cancellingScan ? "Stopping…" : "Stop scan") { model.cancelScan() }.disabled(model.cancellingScan) }
                    else if model.removing { ProgressView().controlSize(.small); Text(model.currentOperation).font(.caption) }
                    Spacer()
                }.padding(.horizontal, 24).padding(.vertical, 12)
                Rule() }
                if model.isInventory {
                    InventoryView()
                } else { ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let issue = model.persistenceIssue { Text(issue).font(.callout).foregroundStyle(Palette.accent) }
                        switch model.section {
                        case .overview: OverviewView()
                        case .growth: GrowthView(growth: growth)
                        case .documents, .applications, .developer: EmptyView()
                        case .review: ReviewView()
                        case .activity: ActivityView()
                        case .reserve: ReserveView()
                        }
                    }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
                } }
                if [.developer, .applications, .documents].contains(model.section) || (!model.selection.isEmpty && model.section != .activity) {
                    Rule()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.selection.isEmpty ? "Select items to clean up" : "\(model.selection.count) selected · \(sizeText(model.selectedBytes)) on disk").fontWeight(.semibold)
                            Text(model.isInventory && model.hiddenSelectionCount > 0 ? "\(model.hiddenSelectionCount) selected outside these results. Review includes all selections." : "Review exact paths and actions before removal.").font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        if !model.selection.isEmpty {
                            Button("Clear selection") { model.selection.removeAll() }.disabled(model.busy || model.removing)
                        }
                        Button("Review and clean…") { model.prepareReview() }.buttonStyle(.borderedProminent)
                            .disabled(model.selection.isEmpty || model.busy || model.removing)
                    }.padding(.horizontal, 24).padding(.vertical, 14).background(Palette.surface)
                }
            }
        }
        .font(.system(size: 14))
        .background(Palette.paper).foregroundStyle(Palette.ink)
        .sheet(isPresented: $model.confirmation) { ConfirmView() }
        .alert("Yeoback", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36).accessibilityHidden(true)
                Text("Yeoback").font(.system(size: 22, weight: .semibold)).tracking(-0.5)
            }.padding(.top, 24)
            Text("Your space, back.").font(.caption).foregroundStyle(Palette.muted).padding(.top, 6)
            VStack(spacing: 6) {
                ForEach(Section.allCases.filter { $0 != .review }) { section in
                    if section == .activity || section == .reserve { Rule().padding(.vertical, 12) }
                    Button {
                        model.section = section
                        if [.developer, .applications].contains(section) && model.reports[section] == nil { model.scan(section) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol).frame(width: 18)
                            Text(section.rawValue).font(.system(size: 14, weight: model.section == section ? .semibold : .regular))
                            Spacer(minLength: 0)
                            if section == .review && !model.selection.isEmpty { Text("\(model.selection.count)").font(.caption.monospacedDigit()) }
                        }.padding(.horizontal, 10).padding(.vertical, 10)
                            .foregroundStyle(Palette.ink)
                            .background(model.section == section ? Palette.tint : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).accessibilityAddTraits(model.section == section ? .isSelected : [])
                }
            }.padding(.top, 32)
            Spacer(minLength: 30)
            Rule()
            VStack(alignment: .leading, spacing: 7) {
                Text(model.monitorLabel).font(.system(size: 12, weight: .semibold))
                Text("\(Int(model.state.targetGB)) GB reserve").font(.caption).foregroundStyle(Palette.muted)
                Text(model.state.monitoring ? "Monitoring while app runs" : "Monitoring paused").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }.padding(.vertical, 20)
        }.padding(.horizontal, 20)
    }
}

struct PageHeading: View {
    let index: String
    let title: String
    let description: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.5).fixedSize(horizontal: false, vertical: true)
            Text(description).font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            PageHeading(index: "", title: "Make room for what’s next.", description: "Start with rebuildable caches. Review every cleanup before it runs.")
            Spacer(minLength: 0)
            Button("Find cleanup") { model.scan(.developer) }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.busy || model.removing)
        }
        Rule()
        if let capacity = model.capacity {
            HStack(alignment: .top, spacing: 20) {
                Metric(label: "Available now", value: Double(capacity.free)/1e9, accent: true)
                Metric(label: "Your reserve", value: model.state.targetGB)
                Metric(label: "Shortfall", value: Double(model.shortfall)/1e9)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.tint)
                    Rectangle().fill(Palette.ink).frame(width: geometry.size.width * min(1, max(0, Double(capacity.total - capacity.free)/Double(max(1, capacity.total)))))
                    Rectangle().fill(Palette.accent).frame(width: 2).offset(x: geometry.size.width * max(0, min(1, 1 - Double(model.targetBytes)/Double(max(1, capacity.total)))))
                }
            }.frame(height: 8).accessibilityLabel("\(sizeText(capacity.free)) available of \(sizeText(capacity.total)); \(Int(model.state.targetGB)) gigabyte reserve")
            HStack {
                Text("\(sizeText(capacity.total - capacity.free)) used / \(sizeText(capacity.total)) volume")
                Spacer()
                Text("Red marker: reserve boundary")
            }.font(.caption).foregroundStyle(Palette.muted)
            HStack {
                Text("Measured \(capacity.date.formatted(date: .omitted, time: .shortened)) · Home volume (\(NSHomeDirectory()))")
                Spacer()
                Button("Refresh") { model.refresh() }.buttonStyle(.link)
            }.font(.caption).foregroundStyle(Palette.muted)
        } else {
            Text("Capacity is unavailable. Refresh to ask macOS for a new reading.")
            Button("Refresh capacity") { model.refresh() }
        }
        Rule()
        VStack(spacing: 0) {
            actionRow("01", "Clean up caches", "Find unused uv data and pip downloads", section: .developer, action: "Find cleanup")
            Rule()
            actionRow("02", "Applications", "Review app bundles before uninstalling", section: .applications, action: "Scan apps")
            Rule()
            actionRow("03", "Documents", "Choose a folder for large and older files", section: .documents, action: "Choose folder")
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Your reserve is a target").font(.callout.weight(.semibold))
            Text("Yeoback checks your reserve every minute while running. Nothing is removed automatically. Moving files to Trash usually does not free space until Trash is emptied in Finder.")
                .font(.callout).foregroundStyle(Palette.muted).lineSpacing(3)
            Button("View reserve forecast") { model.section = .reserve }.buttonStyle(.link)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.tint)
    }

    private func actionRow(_ number: String, _ title: String, _ detail: String, section: Section, action: String) -> some View {
        HStack(spacing: 18) {
            Text(number).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button(action) { model.scan(section) }.disabled(model.busy || model.removing)
        }.padding(.vertical, 20)
    }
}

struct Metric: View {
    let label: String
    let value: Double
    var accent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Eyebrow(text: label)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value.formatted(.number.precision(.fractionLength(1)))).font(.system(size: 40, weight: .medium)).tracking(-2).monospacedDigit()
                Text("GB").font(.caption)
            }.foregroundStyle(accent ? Palette.accent : Palette.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InventoryView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var searchFocused: Bool
    private var kind: CandidateKind { model.inventoryKind }
    private var data: [Candidate] { model.visibleItems }
    private var filter: Binding<InventoryFilter> { Binding(get: { model.filter }, set: { model.filter = $0 }) }
    private var eligible: [Candidate] { data.filter(\.selectable) }
    private var visibleSelected: Int { data.filter { model.selection.contains($0.id) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
            Rule()
            if model.busy && model.scanSection == model.section {
                scanStatus.padding(.horizontal, 24).padding(.vertical, 12).background(Palette.tint)
                Rule()
            }
            HStack(spacing: 12) {
                Text("\(data.count.formatted()) of \(model.inventoryItems.count.formatted()) shown")
                    .fontWeight(.semibold)
                if visibleSelected > 0 { Text("· \(visibleSelected) selected here").foregroundStyle(Palette.muted) }
                Spacer(minLength: 8)
                Button("Select all visible") { model.selectVisible(true) }
                    .disabled(eligible.isEmpty || eligible.allSatisfy { model.selection.contains($0.id) } || model.busy || model.removing)
                    .help("Select all eligible matching results, including rows below the viewport.")
                Button("Deselect visible") { model.selectVisible(false) }
                    .disabled(visibleSelected == 0 || model.busy || model.removing)
            }.font(.caption).padding(.horizontal, 24).padding(.vertical, 12)
            Rule()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let issue = model.persistenceIssue {
                        Text(issue).foregroundStyle(Palette.accent).font(.caption).padding(.vertical, 8)
                    }
                    if !model.busy, let report = model.reports[model.section], report.partial {
                        Label("Partial results — some locations were not inspected.", systemImage: "exclamationmark.circle")
                            .font(.callout.weight(.semibold)).padding(.top, 14)
                        Text("Earlier results from this location remain available. Files are checked again before cleanup.")
                            .font(.caption).foregroundStyle(Palette.muted)
                        ForEach(report.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(Palette.muted).padding(.top, 4) }
                        Button("Scan again") { model.scan(model.section) }.padding(.vertical, 10).disabled(model.removing)
                        Rule()
                    }
                    if data.isEmpty {
                        emptyState.padding(.vertical, 40)
                    } else {
                        ForEach(data) { item in CandidateRow(item: item); Rule() }
                    }
                }.padding(.horizontal, 24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Rule()
            HStack {
                Text(model.reports[model.section]?.summary ?? "Choose a location to start.")
                    .lineLimit(1).help(model.reports[model.section]?.summary ?? "")
                Spacer()
                Text("On-disk estimates").help("Allocated sizes may share APFS storage. They are not guaranteed reclaimed space.")
            }.font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.horizontal, 24).padding(.vertical, 9)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.section.rawValue).font(.system(size: 26, weight: .semibold)).tracking(-0.5)
                    Text(kind == .document ? "Files, SVG drafts and work records. You decide what stays." : kind == .application ? "App bundles move to Trash; support data stays." : "Review rebuildable caches before cleaning.")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                if kind == .document {
                    Menu {
                        Button("Scan Downloads") { model.scanDownloads() }
                        Button("Scan Home folder") { model.scanHomeFolder() }
                        Button("Choose folder…") { model.chooseFolder() }
                    } label: { Label("Choose folder", systemImage: "folder") }.fixedSize()
                        .disabled(model.busy || model.removing)
                }
                Button(model.reports[model.section] == nil ? "Scan" : "Rescan") {
                    if kind == .document && model.documentRoot == nil { model.scanDownloads() }
                    else { model.scan(model.section) }
                }.disabled(model.busy || model.removing)
            }
            if kind == .document, let root = model.documentRoot {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Show folder") { model.reveal(root) }.buttonStyle(.link)
                }.font(.caption).foregroundStyle(Palette.muted).help(root.path)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search name or path", text: filter.search).textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Search name or path")
                if !model.filter.search.isEmpty {
                    Button { model.filter.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
                Button("Find") { searchFocused = true }.keyboardShortcut("f").hidden().frame(width: 0)
            }.padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(searchFocused ? Palette.accent : Palette.line, lineWidth: searchFocused ? 2 : 1))
            HStack(spacing: 10) {
                if kind == .document {
                    Picker("Type", selection: filter.category) {
                        ForEach(FileCategory.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().help("Filter by file type")
                }
                Picker("Size", selection: filter.minimumSize) {
                    ForEach(MinimumSize.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().help("Minimum allocated size")
                Picker("Modified", selection: filter.age) {
                    ForEach(ModifiedAge.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().help("Time since last modification; this does not mean unused")
                Picker("Sort", selection: filter.sort) {
                    ForEach(InventorySort.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().help("Sort results")
            }.controlSize(.regular)
            HStack(spacing: 18) {
                Toggle("Selected only", isOn: filter.selectedOnly).toggleStyle(.checkbox)
                Toggle("Eligible only", isOn: filter.eligibleOnly).toggleStyle(.checkbox)
                    .help("Hide protected and unsupported items")
                Spacer()
                if kind == .document {
                    Menu("Work leftovers") {
                        ForEach([FileCategory.workArtifacts, .svg, .drafts, .records]) { category in
                            Button(category.rawValue) { model.filter.category = category }
                        }
                    }.menuStyle(.borderlessButton).foregroundStyle(Palette.ink).fixedSize()
                        .help("Find SVGs and filename clues from drafts, exports and work records. These are review candidates, not proven unused files.")
                }
                if model.filter.isRestricted {
                    Button("Reset filters") {
                        let sort = model.filter.sort
                        model.filter = InventoryFilter()
                        model.filter.sort = sort
                    }.buttonStyle(.link)
                }
            }.font(.caption)
            if kind == .document && model.filter.category.isArtifactView {
                Text("Filename clues only · AI origin and project usage are not verified. Review before removal.")
                    .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scanStatus: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.cancellingScan ? "Stopping scan…" : "Reading file metadata…").fontWeight(.semibold)
                    Spacer()
                    Text(model.scanStarted, style: .relative).monospacedDigit()
                }
                Text("\(model.scanProgress.visited.formatted()) inspected · \(model.scanProgress.candidates.formatted()) found")
                Text(model.scanProgress.path.isEmpty ? "Preparing this location…" : model.scanProgress.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(Palette.muted)
                if !model.inventoryItems.isEmpty { Text("Previous results remain visible until this scan finishes.").foregroundStyle(Palette.muted) }
            }.font(.caption)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: model.busy && model.scanSection == model.section ? "externaldrive" : "doc.text.magnifyingglass")
                .font(.system(size: 28)).foregroundStyle(Palette.muted).accessibilityHidden(true)
            Text(model.busy && model.scanSection == model.section ? "Your scan is in progress" : model.reports[model.section] == nil ? "Start with a location" : model.filter.isRestricted ? "No results match these filters" : "No supported files found")
                .font(.title3.weight(.semibold))
            Text(model.busy && model.scanSection == model.section ? "Counts update above. Stop the scan to review the entries inspected so far." : model.filter.isRestricted ? "Try a different search or reset the filters. Your selections are preserved." : kind == .document ? "Scan Downloads or choose a personal folder. Hidden files, packages and iCloud-managed items are excluded." : "Run a scan to inspect this category. Protected or unsupported locations remain view only.")
                .font(.callout).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if model.filter.isRestricted {
                Button("Reset filters") { model.filter = InventoryFilter() }
            } else if model.reports[model.section] == nil && !model.busy {
                Button(kind == .document ? "Scan Downloads" : "Start scan") {
                    if kind == .document { model.scanDownloads() } else { model.scan(model.section) }
                }.buttonStyle(.borderedProminent).disabled(model.removing)
            }
        }
    }
}

struct CandidateRow: View {
    @EnvironmentObject var model: AppModel
    let item: Candidate
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if item.selectable {
                Toggle("Select \(item.url.lastPathComponent)", isOn: Binding(get: { model.selection.contains(item.id) }, set: { _ in model.toggle(item) }))
                    .labelsHidden().toggleStyle(.checkbox).disabled(model.removing || model.busy).padding(.top, 3)
            } else { Image(systemName: "eye").foregroundStyle(Palette.muted).frame(width: 16).padding(.top, 3).accessibilityLabel("View only") }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(1).help(item.url.lastPathComponent).textSelection(.enabled)
                if item.kind != .document || !item.selectable {
                    Text(item.reason).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                if item.kind == .cache, item.selectable, let provider = CacheProvider.matching(item.url) {
                    Text(provider.consequence).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Text(item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle).help(item.url.path).textSelection(.enabled)
                if item.kind == .document { Text("Modified \(item.modified.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Palette.muted) }
                if let reason = item.artifactReason {
                    Text(reason).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 8) {
                Text(sizeText(item.bytes)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                HStack(spacing: 8) {
                if item.selectable {
                    Button("Review…") { model.prepareReview(item) }.disabled(model.busy || model.removing)
                        .accessibilityLabel("Review \(item.url.lastPathComponent)")
                }
                Button { model.reveal(item.url) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Show in Finder").accessibilityLabel("Show \(item.url.lastPathComponent) in Finder")
                }
            }.frame(width: 128, alignment: .trailing)
        }.padding(.vertical, 12).padding(.horizontal, 12)
            .background(model.selection.contains(item.id) ? Palette.tint.opacity(0.65) : .clear)
    }
}

struct ReviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(index: "05 / Deliberate cleanup", title: "One last look.", description: "Only your selections appear here. Review the paths and consequences before moving anything.")
        Rule()
        if model.selected.isEmpty {
            Text("Your review is empty.").font(.headline)
            Text("Find cleanup, then select the items you want to review.").foregroundStyle(Palette.muted)
            Button("Find cleanup") { model.scan(.developer) }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Selected allocation")
                    Text(sizeText(model.selectedBytes)).font(.system(size: 36, weight: .medium)).monospacedDigit()
                }
                Spacer()
                Text("\(model.selected.count) \(model.selected.count == 1 ? "item" : "items")").font(.title3)
            }
            Text("Allocated estimate, not guaranteed recovery. The reserve monitors your home volume; selections on other volumes do not reduce its shortfall.").font(.callout).foregroundStyle(Palette.muted)
            LazyVStack(spacing: 0) { ForEach(model.selected) { CandidateRow(item: $0); Rule() } }
            Text("Trash retains the data. For cloud-synced folders, moving a file can propagate to other devices. App removal does not cancel subscriptions or remove support data.")
                .font(.callout).foregroundStyle(Palette.muted).padding(18).background(Palette.tint)
            HStack {
                Button("Clear selection") { model.selection.removeAll() }.disabled(model.removing)
                Spacer()
                Button("Review and clean…") { model.prepareReview() }.buttonStyle(.borderedProminent).disabled(model.busy || model.removing)
            }
        }
    }
}

struct ConfirmView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Clean up \(model.plan.count) \(model.plan.count == 1 ? "item" : "items")?").font(.title2.bold())
            Text("\(sizeText(model.plan.reduce(0) { $0 + $1.bytes })) allocated · review every included location below").font(.callout).foregroundStyle(Palette.muted)
            if model.plan.contains(where: { $0.kind == .cache }) {
                Text("Cache cleanup is permanent and cannot be restored from Trash. Cache size is the amount on disk, not a promise of space recovered.").foregroundStyle(Palette.accent)
            }
            if model.plan.contains(where: { $0.kind != .cache }) {
                Text("Apps and documents move to Trash, which keeps using space until emptied in Finder. Synced files may also disappear on other devices. Close applications first; support data stays in place.").foregroundStyle(Palette.muted)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.plan) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.url.lastPathComponent).fontWeight(.semibold)
                            Text(item.kind == .cache ? CacheProvider.matching(item.url)?.action ?? "Unsupported cache" : "Move to Trash").font(.callout.weight(.medium))
                            Text(item.url.path).font(.caption.monospaced()).textSelection(.enabled)
                            if let provider = item.kind == .cache ? CacheProvider.matching(item.url) : nil {
                                Text(provider.consequence).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 280)
            Text("Only these locations are authorized. Each outcome and a fresh space reading appear after cleanup.").font(.caption)
            HStack {
                Button("Cancel") { model.confirmation = false; model.plan = [] }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.plan.allSatisfy { $0.kind != .cache } ? "Move to Trash" : "Clean selected items", role: .destructive) { model.executePlan() }.buttonStyle(.borderedProminent)
            }
        }.font(.system(size: 14)).padding(32).frame(width: 580).background(Palette.paper).foregroundStyle(Palette.ink)
    }
}

struct ActivityView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(index: "", title: model.removing ? "Cleaning your selections…" : model.lastCleanup != nil ? "Your cleanup results." : "Activity", description: "Each action is recorded here. Available space is measured again after cleanup.")
        if model.removing {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: Double(model.operationCompleted), total: Double(max(1, model.operationTotal)))
                Text("\(model.operationCompleted) of \(model.operationTotal) completed").font(.callout.weight(.semibold))
                Text(model.currentOperation).font(.caption).foregroundStyle(Palette.muted)
                Button(model.stoppingCleanup ? "Stopping after this batch…" : "Stop after current batch") { model.stoppingCleanup = true }
                    .disabled(model.stoppingCleanup)
                Text("Up to 32 documents or one cache operation may finish. Remaining items stay selected.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(18).background(Palette.tint)
        }
        if !model.removing, let pending = model.state.pendingCleanup, !pending.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("An earlier cleanup was interrupted", systemImage: "exclamationmark.triangle").font(.headline)
                Text("These outcomes are unknown. Inspect the original locations and Finder’s Trash before rescanning. Yeoback will never replay these operations automatically.")
                ForEach(pending, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                Button("Record notice in Activity") { model.acknowledgeInterruptedCleanup() }
            }.padding(18).background(Palette.tint)
        }
        if let result = model.lastCleanup {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(result.succeeded) completed · \(result.failed) need attention").font(.title3.weight(.semibold))
                if result.notStarted > 0 { Text("\(result.notStarted) not started · still selected for your review").font(.callout.weight(.medium)) }
                if let before = result.before, let after = result.after {
                    Text("Home-volume available space: \(sizeText(before)) → \(sizeText(after))").font(.headline)
                    Text("Observed change: \(after >= before ? "+" : "−")\(sizeText(abs(after - before))). Other apps and macOS can also change this reading. Items on other volumes do not recover space on the home volume.").font(.caption).foregroundStyle(Palette.muted)
                }
                if result.trashed > 0 { Text("\(result.trashed) moved to Trash. Empty Trash in Finder when you are ready to release that space.").font(.callout) }
                if result.caches > 0 { Text("\(result.caches) cache operations completed. Provider details are recorded below.").font(.callout) }
                Button("Back to \(model.returnSection.rawValue)") { model.section = model.returnSection }.buttonStyle(.borderedProminent)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.tint)
        }
        Rule()
        if model.state.activity.isEmpty {
            Text("No file operations yet.").font(.headline)
            Text("Your confirmed cleanup operations will appear here.").foregroundStyle(Palette.muted)
        }
        ForEach(model.state.activity) { entry in
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: entry.success ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(entry.success ? Palette.ink : Palette.accent)
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.name).fontWeight(.semibold)
                    Text(entry.operation ?? (entry.success ? "Moved to Trash" : "Not confirmed moved")).font(.caption).fontWeight(.semibold)
                    Text(entry.detail).font(.caption).foregroundStyle(Palette.muted).textSelection(.enabled)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Palette.muted)
                    if let destination = entry.destination {
                        Button("Reveal in Trash") { model.reveal(URL(fileURLWithPath: destination)) }.buttonStyle(.link)
                    }
                }
                Spacer()
            }
            Rule()
        }
        Text("Keeps the latest 100 outcomes on this Mac. Finder controls restoration and emptying Trash.").font(.caption).foregroundStyle(Palette.muted)
    }
}

struct ReserveView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        PageHeading(index: "07 / Reserve policy", title: "Leave yourself room.", description: "Set the available space you want on your home volume. Yeoback makes the gap visible and leaves removal decisions with you.")
        Rule()
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance").font(.headline)
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }.pickerStyle(.segmented).frame(maxWidth: 360).labelsHidden()
                .accessibilityLabel("Appearance")
            Text("System follows your Mac. Your choice is saved for the next launch.")
                .font(.caption).foregroundStyle(Palette.muted)
        }
        Rule()
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Available-space target").font(.headline)
                Text("Decimal gigabytes · 1–10,000 GB").font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            TextField("Reserve in GB", value: Binding(get: { model.state.targetGB }, set: { model.setTarget($0) }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 100).accessibilityLabel("Available-space target in gigabytes")
            Text("GB")
        }
        Toggle("Monitor capacity every minute while Yeoback is running", isOn: Binding(get: { model.state.monitoring }, set: { model.state.monitoring = $0; model.save() }))
        if let capacity = model.capacity, model.targetBytes > capacity.total {
            Text("This target exceeds the volume’s total capacity. Choose a smaller target to make it attainable.").foregroundStyle(Palette.accent)
        }
        Text("Monitoring updates the menu-bar reading and reserve status. It does not launch at login, send notifications, empty Trash, or delete files in the background.")
            .font(.callout).foregroundStyle(Palette.muted).lineSpacing(3)
        Rule()
        ForecastView()
        Eyebrow(text: "Recent observations")
        ForEach(Array(model.state.history.suffix(8).reversed().enumerated()), id: \.offset) { _, reading in
            HStack {
                Text(reading.date.formatted(date: .omitted, time: .standard)).foregroundStyle(Palette.muted)
                Spacer()
                Text("\(sizeText(reading.free)) available").monospacedDigit()
            }.font(.callout)
        }
        Text("Stores up to 180 readings locally. Other apps, snapshots and macOS can change availability between readings. This history does not identify which process wrote bytes.")
            .font(.caption).foregroundStyle(Palette.muted)
    }
}
