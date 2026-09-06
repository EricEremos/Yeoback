import SwiftUI
import AppKit

struct GrowthView: View {
    @ObservedObject var growth: GrowthModel
    @EnvironmentObject var app: AppModel
    @State private var search = ""
    @State private var filter = "All"
    private let filters = ["All", "Growing", "Shrinking", "Recurred"]

    var body: some View {
        PageHeading(index: "", title: "Find what keeps growing.", description: "Track a folder over time to see what grows, shrinks, or grows again.")
        if let issue = growth.persistenceIssue { Text(issue).foregroundStyle(Palette.accent) }
        if growth.folders.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72).accessibilityHidden(true)
                Text("Start with one folder.").font(.system(size: 24, weight: .bold))
                Text("Choose a local cache or project folder. Measure it now, then again later.").foregroundStyle(Palette.muted)
                Button("Choose folder…") { growth.chooseFolder() }.buttonStyle(.borderedProminent).controlSize(.large).fixedSize()
                    .disabled(app.busy || app.removing || growth.persistenceIssue != nil)
                Text("Nothing is deleted. Only folder sizes and measurement times are saved.").font(.caption).foregroundStyle(Palette.muted)
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(Palette.tint)
            emptyStateSteps
        } else {
            folderToolbar
            if let folder = growth.selected {
                folderPathRow(folder)
                if growth.busy {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Measuring folder… \(growth.visited.formatted()) entries inspected").font(.callout.monospacedDigit())
                        Spacer()
                        Button("Cancel") { growth.cancel() }.fixedSize()
                    }.padding(18).background(Palette.tint)
                }
                if let issue = growth.issue {
                    Text(issue + " Your last complete measurement is preserved.").font(.callout).foregroundStyle(Palette.accent)
                }
                if let current = folder.snapshots.last {
                    measurements(folder, current)
                } else if !growth.busy {
                    Text("No complete measurement yet. Try a smaller local folder if a scan reaches its limit.").foregroundStyle(Palette.muted)
                }
                HStack {
                    Text("\(folder.snapshots.count) of 12 measurements kept").font(.caption).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Stop tracking") { growth.stopTracking() }.fixedSize().disabled(growth.busy)
                        .help("Remove this folder’s saved measurements. No files are deleted.")
                }
            }
        }
        Rule()
        Text("Manual measurements · up to 3 folders · local metadata only").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
        Text("Sizes are observed allocations, not promised reclaimable space. APFS clones can share storage. Live changes, excluded links, and hardlink deduplication affect totals. Recurrence means growth followed a measured fall; it does not identify an app or prove cleanup caused it.")
            .font(.caption).foregroundStyle(Palette.muted).lineSpacing(3)
    }

    @ViewBuilder private func measurements(_ folder: TrackedFolder, _ current: GrowthSnapshot) -> some View {
        let previous = folder.snapshots.dropLast().last
        let changes = previous.map { GrowthLedger.changes(previous: $0, current: current) } ?? []
        let deltas = Dictionary(uniqueKeysWithValues: changes.map { ($0.name, $0.delta) })
        let names = Set(current.buckets.keys).union(previous?.buckets.keys.map { $0 } ?? [])
        let rows = names.filter { name in
            let delta = deltas[name, default: 0]
            return (search.isEmpty || name.localizedCaseInsensitiveContains(search)) &&
                (filter == "All" || (filter == "Growing" && delta > 0) || (filter == "Shrinking" && delta < 0) ||
                 (filter == "Recurred" && GrowthLedger.recurrenceLabel(folder.snapshots, name: name) != nil))
        }.sorted { a, b in
            let av = deltas[a, default: 0], bv = deltas[b, default: 0]
            if av != bv { return av > bv }
            let ac = current.buckets[a, default: 0], bc = current.buckets[b, default: 0]
            return ac == bc ? a < b : ac > bc
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(sizeText(current.buckets.values.reduce(0, +))).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
            Text("Measured \(current.date.formatted(date: .abbreviated, time: .standard)) · \(current.visited.formatted()) entries")
                .font(.caption).foregroundStyle(Palette.muted)
            if let previous {
                Text("Changes since \(previous.date.formatted(date: .abbreviated, time: .standard))").font(.caption).foregroundStyle(Palette.muted)
            } else {
                Text("Baseline saved. Measure again later to see changes.").font(.callout.weight(.semibold))
            }
        }.padding(.vertical, 8)
        HStack(spacing: 14) {
            TextField("Search subfolders", text: $search).textFieldStyle(.roundedBorder)
            Picker("Show", selection: $filter) { ForEach(filters, id: \.self) { Text($0) } }.frame(width: 200)
        }
        HStack { Text("Folder / largest growth first"); Spacer(); Text("Allocated").frame(width: 100, alignment: .trailing); Text("Change").frame(width: 100, alignment: .trailing) }
            .font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
        VStack(spacing: 0) {
            if rows.isEmpty { Text("No folders match this filter.").foregroundStyle(Palette.muted).padding(24) }
            ForEach(rows, id: \.self) { name in
                Rule()
                HStack(spacing: 12) {
                    Image(systemName: name == "(Files in folder)" ? "doc" : "folder").foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).lineLimit(2).truncationMode(.middle).help(name).textSelection(.enabled)
                        if let label = GrowthLedger.recurrenceLabel(folder.snapshots, name: name) {
                            Text(label).font(.caption).foregroundStyle(Palette.accent)
                        }
                    }
                    Spacer()
                    Text(sizeText(current.buckets[name, default: 0])).frame(width: 100, alignment: .trailing)
                    Text(previous == nil ? "—" : deltaText(deltas[name, default: 0])).frame(width: 100, alignment: .trailing)
                        .foregroundStyle(deltas[name, default: 0] > 0 ? Palette.accent : Palette.muted)
                }.font(.callout).monospacedDigit().padding(.vertical, 16)
            }
        }
    }

    private var emptyStateSteps: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                emptyStateStep("01", "Choose a folder")
                emptyStateStep("02", "Measure changes")
                emptyStateStep("03", "Investigate in Finder")
            }
            VStack(alignment: .leading, spacing: 10) {
                emptyStateStep("01", "Choose a folder")
                emptyStateStep("02", "Measure changes")
                emptyStateStep("03", "Investigate in Finder")
            }
        }
        .font(.callout.weight(.semibold))
    }

    private func emptyStateStep(_ number: String, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var folderToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                folderPicker
                Spacer(minLength: 0)
                folderActions
            }
            VStack(alignment: .leading, spacing: 10) {
                folderPicker.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) { folderActions }
            }
        }
    }

    private var folderPicker: some View {
        Picker("Folder", selection: $growth.selectedID) {
            ForEach(growth.folders) { folder in
                Text(folder.url.lastPathComponent)
                    .tag(Optional(folder.id))
                    .help(folder.url.lastPathComponent)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 300, alignment: .leading)
        .disabled(growth.busy)
    }

    @ViewBuilder private var folderActions: some View {
        Button("Add folder…") { growth.chooseFolder() }
            .fixedSize()
            .disabled(growth.folders.count >= 3 || growth.busy || app.busy || app.removing || growth.persistenceIssue != nil)
        Button("Measure again") { growth.measure() }
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .disabled(growth.busy || app.busy || app.removing || growth.persistenceIssue != nil)
    }

    private func folderPathRow(_ folder: TrackedFolder) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                folderPathLabel(folder.path)
                    .frame(maxWidth: .infinity, alignment: .leading)
                finderButton(for: folder)
            }
            VStack(alignment: .leading, spacing: 8) {
                folderPathLabel(folder.path)
                finderButton(for: folder)
            }
        }
    }

    private func folderPathLabel(_ path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
            Text(path)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
        }
        .font(.caption)
        .foregroundStyle(Palette.muted)
    }

    private func finderButton(for folder: TrackedFolder) -> some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
            .fixedSize()
    }

    private func deltaText(_ bytes: Int64) -> String {
        bytes == 0 ? "No change" : "\(bytes > 0 ? "+" : "−")\(sizeText(abs(bytes)))"
    }
}
