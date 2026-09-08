import SwiftUI
import AppKit

struct GrowthView: View {
    @ObservedObject var growth: GrowthModel
    @EnvironmentObject var app: AppModel
    @State private var search = ""
    @State private var filter = "All"
    private let filters = ["All", "Growing", "Shrinking", "Recurred"]

    var body: some View {
        PageHeading(index: "", title: "Growth", description: "")
        if let issue = growth.persistenceIssue { Text(issue).foregroundStyle(Palette.accent) }
        if growth.folders.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                Text("Compare a folder’s size over time.").foregroundStyle(Palette.muted)
                Button("Choose folder…") { growth.chooseFolder() }.buttonStyle(.borderedProminent).controlSize(.large).fixedSize()
                    .disabled(app.busy || app.removing || growth.persistenceIssue != nil)
            }.padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
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
                    }.padding(.vertical, 12)
                }
                if let issue = growth.issue {
                    Text(issue + " Your last complete measurement is preserved.").font(.callout).foregroundStyle(Palette.accent)
                }
                if !growth.inaccessiblePaths.isEmpty {
                    DisclosureGroup("Access needed") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(growth.inaccessiblePaths, id: \.self) { path in
                                Text(path).textSelection(.enabled)
                            }
                            Text("Enable Yeoback in Full Disk Access, relaunch, then measure again. File ownership and macOS protections still apply.")
                            Button("Open Full Disk Access…") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                            }
                        }.font(.caption).padding(.top, 8)
                    }
                }
                if let partial = growth.incompleteMeasurement {
                    measurements(folder, partial, incomplete: true)
                } else if let current = folder.snapshots.last {
                    measurements(folder, current)
                } else if !growth.busy {
                    Text("Measure this folder to save a baseline.").foregroundStyle(Palette.muted)
                }
            }
        }
        Rule()
        DisclosureGroup("Measurement details") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Up to \(GrowthModel.maximumFolders) folders · 12 readings each · 10 million entries or 1 hour per scan")
                Text("Allocated sizes can share APFS storage and are not reclaimable-space estimates. Recurrence describes observed changes, not their cause.")
            }.font(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
        }
    }

    @ViewBuilder private func measurements(_ folder: TrackedFolder, _ current: GrowthSnapshot, incomplete: Bool = false) -> some View {
        let previous = incomplete ? nil : folder.snapshots.dropLast().last
        let changes = previous.map { GrowthLedger.changes(previous: $0, current: current) } ?? []
        let deltas = Dictionary(uniqueKeysWithValues: changes.map { ($0.name, $0.delta) })
        let names = Set(current.buckets.keys).union(previous?.buckets.keys.map { $0 } ?? [])
        let rows = names.filter { name in
            let delta = deltas[name, default: 0]
            return (search.isEmpty || name.localizedCaseInsensitiveContains(search)) &&
                (previous == nil || filter == "All" || (filter == "Growing" && delta > 0) || (filter == "Shrinking" && delta < 0) ||
                 (filter == "Recurred" && !incomplete && GrowthLedger.recurrenceLabel(folder.snapshots, name: name) != nil))
        }.sorted { a, b in
            let av = deltas[a, default: 0], bv = deltas[b, default: 0]
            if av != bv { return av > bv }
            let ac = current.buckets[a, default: 0], bc = current.buckets[b, default: 0]
            return ac == bc ? a < b : ac > bc
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(sizeText(current.buckets.values.reduce(0, +))).font(.system(size: 40, weight: .medium)).tracking(-1).monospacedDigit()
            Text("\(incomplete ? "Measured so far" : "Measured") \(current.date.formatted(date: .abbreviated, time: .standard)) · \(current.visited.formatted()) entries")
                .font(.caption).foregroundStyle(Palette.muted)
            if incomplete {
                Text("Incomplete coverage. These sizes cover inspected entries only; this result is not saved or used for growth comparisons.").font(.callout).foregroundStyle(Palette.muted)
            } else if let previous {
                Text("Changes since \(previous.date.formatted(date: .abbreviated, time: .standard))").font(.caption).foregroundStyle(Palette.muted)
            } else {
                Text("Baseline saved. Measure again later to see changes.").font(.callout.weight(.semibold))
            }
        }.padding(.vertical, 8)
        HStack(spacing: 14) {
            TextField("Search subfolders", text: $search).textFieldStyle(.roundedBorder)
            if previous != nil {
                Picker("Show", selection: $filter) { ForEach(filters, id: \.self) { Text($0) } }.frame(width: 200)
            }
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
                        if !incomplete, let label = GrowthLedger.recurrenceLabel(folder.snapshots, name: name) {
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
        Menu("Folder actions") {
            Button("Add folder…") { growth.chooseFolder() }
                .disabled(growth.folders.count >= GrowthModel.maximumFolders || growth.busy || app.busy || app.removing || growth.persistenceIssue != nil)
            if let folder = growth.selected {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                Button("Stop tracking") { growth.stopTracking() }.disabled(growth.busy)
                    .help("Remove saved measurements only. No files are deleted.")
            }
        }.fixedSize()
        Button("Measure") { growth.measure() }
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .disabled(growth.busy || app.busy || app.removing || growth.persistenceIssue != nil)
    }

    private func folderPathRow(_ folder: TrackedFolder) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                folderPathLabel(folder.path)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 8) {
                folderPathLabel(folder.path)
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

    private func deltaText(_ bytes: Int64) -> String {
        bytes == 0 ? "No change" : "\(bytes > 0 ? "+" : "−")\(sizeText(abs(bytes)))"
    }
}
