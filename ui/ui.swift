// MARK: - UI

import AppKit
import Foundation
import SwiftUI

enum DiskScreen: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case large = "Large Files"
    case old = "Unused Files"
    case duplicates = "Duplicates"
    case junk = "Junk & Caches"
    case unusedApps = "Unused Apps"
    case spaceLens = "Space Lens"
    case memory = "Memory"
    case cleaner = "Cleaner"
    case about = "About"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview:   return "chart.pie.fill"
        case .large:      return "doc.fill"
        case .old:        return "clock.badge.exclamationmark"
        case .duplicates: return "doc.on.doc.fill"
        case .junk:       return "trash.fill"
        case .unusedApps: return "app.badge"
        case .spaceLens:  return "square.grid.3x3.fill"
        case .memory:     return "memorychip"
        case .cleaner:    return "sparkles"
        case .about:      return "info.circle"
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}

struct EmptyState: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActionOverlay: View {
    @ObservedObject var scanner: DiskScanner

    var body: some View {
        if scanner.isPerformingAction {
            ZStack {
                Color.black.opacity(0.2).ignoresSafeArea()
                VStack(spacing: 12) {
                    if scanner.actionProgress > 0 {
                        ProgressView(value: scanner.actionProgress)
                            .frame(width: 220)
                    } else {
                        ProgressView()
                    }
                    Text(scanner.actionMessage)
                        .font(.callout)
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
                .shadow(radius: 8)
            }
        }
    }
}

struct TopBar: View {
    @ObservedObject var scanner: DiskScanner
    @ObservedObject var monitor = SystemMonitor.shared

    var body: some View {
        HStack(spacing: 12) {
            Text("Disk Store").font(.title2.bold())
            if let root = scanner.rootURL, !scanner.isScanning {
                Text(root.displayPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button {
                monitor.menuBarEnabled.toggle()
            } label: {
                Image(systemName: "rays")
                    .foregroundStyle(monitor.menuBarEnabled ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(monitor.menuBarEnabled ? "Hide menu bar monitor" : "Show menu bar monitor")
            if scanner.isScanning {
                ProgressView(value: scanner.progress).frame(width: 200)
                Text(scanner.phase.rawValue)
                    .font(.caption).foregroundStyle(.secondary)
                Button("Cancel") { scanner.cancel() }
            } else {
                Button { pickFolder() } label: {
                    Label(scanner.rootURL == nil ? "Choose Folder" : "Scan Again",
                          systemImage: "folder.badge.plus")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = scanner.rootURL ?? FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            scanner.scan(url: url)
        }
    }
}

struct FileRow: View {
    let file: FileEntry
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.body.weight(.medium))
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(file.folder).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if file.category != .other {
                        Text(file.category.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.14))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Text(file.size.formattedBytes)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: { Image(systemName: "magnifyingglass.circle") }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Move to Trash")
        }
        .padding(.vertical, 3)
    }
}

struct OverviewView: View {
    @ObservedObject var scanner: DiskScanner

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Overview").font(.largeTitle.bold())

                HStack(spacing: 14) {
                    StatCard(title: "Total", value: scanner.totalSize.formattedBytes,
                             icon: "internaldrive.fill", tint: .blue)
                    StatCard(title: "Files", value: "\(scanner.fileCount.formatted())",
                             icon: "doc.fill", tint: .purple)
                    StatCard(title: "Folders", value: "\(scanner.folderCount.formatted())",
                             icon: "folder.fill", tint: .indigo)
                    StatCard(title: "Duplicate waste", value: scanner.duplicateWasted.formattedBytes,
                             icon: "doc.on.doc.fill", tint: .orange)
                }

                if !scanner.topFolders.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(scanner.topFolders.prefix(20)) { folder in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(folder.url.lastPathComponent)
                                            .lineLimit(1).truncationMode(.middle)
                                        Text(folder.url.displayPath)
                                            .font(.caption2).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    .frame(width: 260, alignment: .leading)

                                    GeometryReader { geo in
                                        let ratio = scanner.totalSize > 0
                                            ? CGFloat(Double(folder.size) / Double(scanner.totalSize)) : 0
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.secondary.opacity(0.15))
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.accentColor.opacity(0.75))
                                                .frame(width: max(3, geo.size.width * ratio))
                                        }
                                    }
                                    .frame(height: 12)

                                    Text(folder.size.formattedBytes)
                                        .font(.caption.monospacedDigit())
                                        .frame(width: 90, alignment: .trailing)
                                }
                            }
                        }
                        .padding(6)
                    } label: {
                        Label("Largest folders", systemImage: "folder")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LargeFilesView: View {
    @ObservedObject var scanner: DiskScanner
    @State private var categoryFilter: FileCategory?

    private var filteredFiles: [FileEntry] {
        guard let filter = categoryFilter else { return scanner.largeFiles }
        return scanner.largeFiles.filter { $0.category == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Large Files").font(.largeTitle.bold())
                Spacer()
                if !scanner.largeFiles.isEmpty {
                    Picker("Filter", selection: $categoryFilter) {
                        Text("All").tag(FileCategory?.none)
                        ForEach(FileCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(FileCategory?.some(category))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                    Text("\(filteredFiles.count) files")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)

            if scanner.largeFiles.isEmpty {
                EmptyState(text: "No large files found in the scanned folder.")
            } else {
                List(filteredFiles) { file in
                    FileRow(file: file) {
                        scanner.trash([file.url]) { scanner.removeFile(file.url) }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct OldFilesView: View {
    @ObservedObject var scanner: DiskScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Unused Files").font(.largeTitle.bold())
                Spacer()
                Text("Not accessed in 6+ months")
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            if scanner.oldFiles.isEmpty {
                EmptyState(text: "No unused files found.")
            } else {
                List(scanner.oldFiles) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name).font(.body.weight(.medium))
                                .lineLimit(1).truncationMode(.middle)
                            HStack(spacing: 6) {
                                Text(file.folder).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                if file.category != .other {
                                    Text(file.category.rawValue)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.14))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        Spacer()
                        Text("last opened \(file.accessed.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(file.size.formattedBytes)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        } label: { Image(systemName: "magnifyingglass.circle") }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            scanner.trash([file.url]) { scanner.removeFile(file.url) }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }
        }
    }
}

struct DuplicatesView: View {
    @ObservedObject var scanner: DiskScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Duplicates").font(.largeTitle.bold())
                Spacer()
                Text("Can free \(scanner.duplicateWasted.formattedBytes)")
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            if scanner.duplicates.isEmpty {
                EmptyState(text: "No duplicate files (≥ 1 MB) found.")
            } else {
                List {
                    ForEach(scanner.duplicates) { group in
                        Section {
                            ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name).font(.body.weight(.medium))
                                        Text(file.folder).font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    if index == 0 {
                                        Text("KEEP")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.15))
                                            .foregroundStyle(.green)
                                            .clipShape(Capsule())
                                    } else {
                                        Button {
                                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                        } label: { Image(systemName: "magnifyingglass.circle") }
                                            .buttonStyle(.borderless)
                                        Button(role: .destructive) {
                                            scanner.trash([file.url]) { scanner.removeFile(file.url) }
                                        } label: { Image(systemName: "trash") }
                                            .buttonStyle(.borderless)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text("\(group.files.count) × \(group.files.first?.name ?? "") — \(group.fileSize.formattedBytes) each · wastes \(group.wastedBytes.formattedBytes)")
                                .font(.caption)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct JunkView: View {
    @ObservedObject var scanner: DiskScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("System Junk").font(.largeTitle.bold())
                Text("User caches, logs, Xcode build artifacts, software update leftovers, mail downloads and universal binaries. Review before cleaning.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)

            if scanner.junkItems.isEmpty {
                EmptyState(text: "No system junk found.")
            } else {
                List(scanner.junkItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: item.category)).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body.weight(.medium))
                                .lineLimit(1).truncationMode(.middle)
                            Text("\(item.category.rawValue) — \(item.url.displayPath)")
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(item.size.formattedBytes)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: { Image(systemName: "magnifyingglass.circle") }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                        if item.category != .universal {
                            Button(role: .destructive) {
                                scanner.trash([item.url]) { scanner.removeJunkItem(item.url) }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Move to Trash")
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }
        }
    }

    private func icon(for category: JunkCategory) -> String {
        switch category {
        case .caches:         return "internaldrive"
        case .logs:           return "doc.text"
        case .xcode:          return "hammer"
        case .softwareUpdate: return "arrow.down.circle"
        case .mail:           return "envelope"
        case .universal:      return "cpu"
        }
    }
}

struct UnusedAppsView: View {
    @ObservedObject var scanner: DiskScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Unused Apps").font(.largeTitle.bold())
                Spacer()
                if scanner.isRefreshingCleaner { ProgressView().controlSize(.small) }
                Button("Rescan") { scanner.refreshCleanerData() }
            }
            .padding(24)

            if scanner.unusedApps.isEmpty {
                EmptyState(text: scanner.isRefreshingCleaner
                           ? "Looking for unused apps…"
                           : "No unused apps found (not opened in 6+ months).")
            } else {
                List(scanner.unusedApps) { app in
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.body.weight(.medium))
                                .lineLimit(1).truncationMode(.middle)
                            Text("last used \(app.lastUsed?.formatted(date: .abbreviated, time: .omitted) ?? "never")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(app.size.formattedBytes)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([app.url])
                        } label: { Image(systemName: "magnifyingglass.circle") }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                        Button(role: .destructive) {
                            scanner.uninstallApp(app)
                        } label: { Label("Uninstall", systemImage: "trash") }
                            .help("Move app to Trash")
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }
        }
    }
}

struct MemoryView: View {
    @ObservedObject var scanner: DiskScanner

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Memory").font(.largeTitle.bold())
                    Spacer()
                    Button("Refresh") { scanner.refreshMemory() }
                }

                if let stats = scanner.memoryStats {
                    HStack(spacing: 14) {
                        StatCard(title: "Total", value: stats.totalBytes.formattedBytes,
                                 icon: "memorychip", tint: .blue)
                        StatCard(title: "Used", value: stats.usedBytes.formattedBytes,
                                 icon: "chart.bar.fill", tint: .orange)
                        StatCard(title: "Free", value: stats.freeBytes.formattedBytes,
                                 icon: "gauge", tint: .green)
                        StatCard(title: "Cached files", value: stats.cachedBytes.formattedBytes,
                                 icon: "externaldrive.fill", tint: .purple)
                    }
                    HStack(spacing: 14) {
                        StatCard(title: "Active", value: stats.activeBytes.formattedBytes,
                                 icon: "bolt.fill", tint: .red)
                        StatCard(title: "Inactive", value: stats.inactiveBytes.formattedBytes,
                                 icon: "moon.fill", tint: .indigo)
                        StatCard(title: "Wired", value: stats.wiredBytes.formattedBytes,
                                 icon: "lock.fill", tint: .gray)
                        StatCard(title: "Compressed", value: stats.compressedBytes.formattedBytes,
                                 icon: "arrow.down.right.and.arrow.up.left", tint: .pink)
                    }

                    HStack(spacing: 12) {
                        Label("Pressure: \(stats.pressureLabel)", systemImage: "waveform.path.ecg")
                            .foregroundStyle(stats.pressureLevel >= 2 ? .orange : .green)
                        Spacer()
                        Button { scanner.freeRAM() } label: {
                            Label("Free Up RAM", systemImage: "sparkles")
                        }
                    }
                } else {
                    EmptyState(text: "No memory information available.")
                }

                if let notice = scanner.actionNotice {
                    Text(notice).font(.callout).foregroundStyle(.secondary)
                }

                if !scanner.memoryApps.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(scanner.memoryApps) { app in
                                HStack {
                                    Text(app.name)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(app.memoryBytes.formattedBytes)
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(6)
                    } label: {
                        Label("Top apps by memory", systemImage: "app.badge")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { scanner.refreshMemory() }
    }
}

struct CleanerView: View {
    @ObservedObject var scanner: DiskScanner
    @ObservedObject var cleaner = DailyCleaner.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cleaner").font(.largeTitle.bold())
                Spacer()
                if scanner.isRefreshingCleaner { ProgressView().controlSize(.small) }
                Button("Rescan") { scanner.refreshCleanerData() }
            }
            .padding(24)

            List {
                Section("Trash") {
                    HStack(spacing: 12) {
                        Label("Trash", systemImage: "trash")
                        Spacer()
                        Text(scanner.trashSize.formattedBytes)
                            .foregroundStyle(.secondary)
                        Button("Empty Trash") { scanner.emptyTrash() }
                        Button("Empty All Bins") { scanner.emptyAllTrashBins() }
                            .help("Empty the user Trash and per-volume Trash folders on all mounted disks")
                    }
                }

                Section {
                    if scanner.leftovers.isEmpty {
                        Text(scanner.isRefreshingCleaner ? "Looking for leftovers…" : "No leftovers found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(scanner.leftovers) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "shippingbox").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.body.weight(.medium))
                                        .lineLimit(1).truncationMode(.middle)
                                    Text("\(item.location) — \(item.url.displayPath)")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(item.size.formattedBytes)
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .trailing)
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                } label: { Image(systemName: "magnifyingglass.circle") }
                                    .buttonStyle(.borderless)
                                    .help("Reveal in Finder")
                                Button(role: .destructive) {
                                    scanner.deleteLeftover(item)
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Move to Trash")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } header: {
                    HStack {
                        Text("Leftovers from uninstalled apps")
                        Spacer()
                        if !scanner.leftovers.isEmpty {
                            Button("Clean All") { scanner.cleanLeftovers() }
                                .buttonStyle(.borderless)
                        }
                    }
                }

                Section("Automatic Daily Cleaning") {
                    Toggle("Enable daily cleaning", isOn: $cleaner.enabled)
                    if cleaner.enabled {
                        Picker("Run at", selection: $cleaner.hour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(Self.hourLabel(hour)).tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                        Toggle("Empty Trash", isOn: $cleaner.emptyTrashEnabled)
                        Toggle("Clean leftovers", isOn: $cleaner.cleanLeftoversEnabled)
                        Toggle("Clear caches", isOn: $cleaner.clearCachesEnabled)
                        Toggle("Clear logs", isOn: $cleaner.clearLogsEnabled)
                        if let summary = cleaner.lastCleanSummary {
                            LabeledContent("Last run") {
                                Text("\(summary) · \(cleaner.lastCleanDate?.formatted(date: .abbreviated, time: .shortened) ?? "")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Run Now") { cleaner.runDailyClean() }
                            .disabled(cleaner.isCleaning)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Squarified treemap layout (Bruls et al.) — produces rectangles with good aspect ratios.
private enum Treemap {
    static func layout(values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        guard !values.isEmpty, rect.width > 0, rect.height > 0 else { return result }
        let total = values.reduce(0, +)
        guard total > 0 else { return result }

        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }
        let indices = Array(values.indices).sorted { values[$0] > values[$1] }
        var remaining = indices
        var currentRect = rect
        var currentTotal = areas.reduce(0, +)

        while !remaining.isEmpty {
            let side = min(currentRect.width, currentRect.height)
            var rowCount = 1
            var bestWorst = worst(row: Array(remaining[0..<1]), areas: areas, side: side)

            while rowCount < remaining.count {
                let candidate = Array(remaining[0...rowCount])
                let w = worst(row: candidate, areas: areas, side: side)
                if w <= bestWorst {
                    bestWorst = w
                    rowCount += 1
                } else {
                    break
                }
            }

            let row = Array(remaining[0..<rowCount])
            let rowSum = row.reduce(0.0) { $0 + areas[$1] }
            let rowFraction = rowSum / currentTotal

            var rowRect = currentRect
            if currentRect.width >= currentRect.height {
                rowRect.size.width = currentRect.width * CGFloat(rowFraction)
            } else {
                rowRect.size.height = currentRect.height * CGFloat(rowFraction)
            }

            var offset: CGFloat = 0
            for index in row {
                var r = rowRect
                let fraction = rowSum > 0 ? CGFloat(areas[index] / rowSum) : 0
                if currentRect.width >= currentRect.height {
                    r.origin.y = rowRect.minY + offset
                    r.size.height = rowRect.height * fraction
                } else {
                    r.origin.x = rowRect.minX + offset
                    r.size.width = rowRect.width * fraction
                }
                offset += (currentRect.width >= currentRect.height ? r.height : r.width)
                result[index] = r
            }

            if currentRect.width >= currentRect.height {
                currentRect.origin.x = rowRect.maxX
                currentRect.size.width -= rowRect.width
            } else {
                currentRect.origin.y = rowRect.maxY
                currentRect.size.height -= rowRect.height
            }
            currentTotal -= rowSum
            remaining = Array(remaining[rowCount...])
        }
        return result
    }

    private static func worst(row: [Int], areas: [Double], side: CGFloat) -> CGFloat {
        let s = row.reduce(0.0) { $0 + areas[$1] }
        guard s > 0 else { return .greatestFiniteMagnitude }
        let rowAreas = row.map { areas[$0] }
        let rMax = rowAreas.max() ?? 0
        let rMin = rowAreas.min() ?? 0
        let w = Double(side)
        let first = (w * w * rMax) / (s * s)
        let second = (s * s) / (w * w * rMin)
        return CGFloat(max(first, second))
    }
}

@MainActor
final class SpaceLensModel: ObservableObject {
    @Published var path: [URL] = []
    @Published var nodes: [SpaceNode] = []
    @Published var isLoading = false
    @Published var selectedNode: SpaceNode?

    var rootURL: URL?
    var topFolders: [FolderSize] = []

    func configure(rootURL: URL?, topFolders: [FolderSize]) {
        self.rootURL = rootURL
        self.topFolders = topFolders
        objectWillChange.send()
    }

    var displayNodes: [SpaceNode] {
        if path.isEmpty {
            return topFolders.map {
                SpaceNode(name: $0.url.lastPathComponent, url: $0.url, size: $0.size, isDirectory: true)
            }
        }
        return nodes
    }

    var totalSize: Int64 {
        if path.isEmpty { return topFolders.reduce(0) { $0 + $1.size } }
        return nodes.reduce(0) { $0 + $1.size }
    }

    func open(_ node: SpaceNode) {
        selectedNode = node
        guard node.isDirectory else {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
            return
        }
        path.append(node.url)
        nodes = []
        load(node.url)
    }

    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
        nodes = []
        selectedNode = nil
        if let current = path.last { load(current) }
    }

    func goToRoot() {
        path = []
        nodes = []
        selectedNode = nil
    }

    func goTo(index: Int) {
        guard index >= 0, index < path.count else { return }
        path = Array(path.prefix(index + 1))
        nodes = []
        selectedNode = nil
        load(path[index])
    }

    private func load(_ url: URL) {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let result = DiskScanner.spaceNodes(in: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.nodes = result
                self.isLoading = false
            }
        }
    }
}

struct SpaceLensView: View {
    @ObservedObject var scanner: DiskScanner
    @StateObject private var model = SpaceLensModel()
    @State private var hoveredNode: SpaceNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if model.path.isEmpty && model.displayNodes.isEmpty {
                EmptyState(text: "Run a scan to see the storage map.")
            } else if model.isLoading && model.displayNodes.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Scanning folder…")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                map
                statusBar
            }
        }
        .task(id: scanner.topFolders.count) {
            model.configure(rootURL: scanner.rootURL, topFolders: scanner.topFolders)
        }
        .onAppear {
            model.configure(rootURL: scanner.rootURL, topFolders: scanner.topFolders)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Space Lens").font(.largeTitle.bold())
                Spacer()
                if !model.path.isEmpty {
                    Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                }
            }

            HStack(spacing: 4) {
                Button("Home") { model.goToRoot() }
                ForEach(Array(model.path.enumerated()), id: \.offset) { index, url in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    Button(url.lastPathComponent) { model.goTo(index: index) }
                }
                if model.isLoading {
                    ProgressView().controlSize(.small).padding(.leading, 8)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var map: some View {
        GeometryReader { geo in
            let nodes = model.displayNodes
            let values = nodes.map { Double($0.size) }
            let layout = Treemap.layout(values: values, in: CGRect(origin: .zero, size: geo.size))

            Canvas { context, _ in
                for (index, node) in nodes.enumerated() where index < layout.count {
                    let rect = layout[index].insetBy(dx: 1.5, dy: 1.5)
                    guard rect.width > 1, rect.height > 1 else { continue }
                    let shape = Path(roundedRect: rect, cornerRadius: 4)
                    context.fill(shape, with: .color(Self.color(for: node, index: index)))
                    if hoveredNode?.id == node.id || model.selectedNode?.id == node.id {
                        context.stroke(shape, with: .color(.white), lineWidth: 2.5)
                    }
                    if rect.width > 60, rect.height > 22 {
                        context.draw(
                            Text(node.name)
                                .font(.caption2.bold())
                                .foregroundColor(.white),
                            at: CGPoint(x: rect.midX, y: rect.midY)
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredNode = Self.hitTest(location: location, nodes: nodes, layout: layout)
                case .ended:
                    hoveredNode = nil
                }
            }
            .onTapGesture { location in
                if let node = Self.hitTest(location: location, nodes: nodes, layout: layout) {
                    model.open(node)
                }
            }
        }
        .frame(minHeight: 360)
        .padding(.horizontal, 24)
    }

    private var statusBar: some View {
        let info = hoveredNode ?? model.selectedNode
        return HStack(spacing: 12) {
            if let info {
                Image(systemName: info.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(.secondary)
                Text(info.name)
                    .fontWeight(.medium)
                    .lineLimit(1).truncationMode(.middle)
                Text(info.size.formattedBytes)
                    .foregroundStyle(.secondary)
                if !info.isDirectory {
                    Text(info.category.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([info.url])
                }
            } else {
                Text("Hover a block to inspect it · click a folder to zoom in · click a file to reveal it")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(24)
    }

    private static func hitTest(location: CGPoint, nodes: [SpaceNode], layout: [CGRect]) -> SpaceNode? {
        for (index, node) in nodes.enumerated() where index < layout.count {
            if layout[index].contains(location) { return node }
        }
        return nil
    }

    private static func color(for node: SpaceNode, index: Int) -> Color {
        if node.isDirectory {
            let palette: [Color] = [
                Color(red: 0.33, green: 0.50, blue: 0.94),
                Color(red: 0.46, green: 0.35, blue: 0.96),
                Color(red: 0.29, green: 0.69, blue: 0.90),
                Color(red: 0.43, green: 0.67, blue: 0.41),
                Color(red: 0.95, green: 0.61, blue: 0.29),
                Color(red: 0.92, green: 0.44, blue: 0.54),
            ]
            return palette[index % palette.count]
        }
        switch node.category {
        case .media:    return Color(red: 0.90, green: 0.36, blue: 0.52)
        case .sql:      return Color(red: 0.96, green: 0.69, blue: 0.29)
        case .archive:  return Color(red: 0.94, green: 0.57, blue: 0.26)
        case .image:    return Color(red: 0.33, green: 0.75, blue: 0.58)
        case .document: return Color(red: 0.36, green: 0.65, blue: 0.93)
        case .app:      return Color(red: 0.52, green: 0.76, blue: 0.40)
        case .other:    return Color(red: 0.58, green: 0.60, blue: 0.66)
        }
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Disk Store").font(.largeTitle.bold())
            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("A lightweight disk space analyzer and system cleaner for macOS.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Divider().frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 8) {
                Label("Disk usage, large files, duplicates and junk cleanup", systemImage: "internaldrive")
                Label("Unused apps and leftover detection", systemImage: "app.badge")
                Label("Memory monitor and top apps by RAM", systemImage: "memorychip")
                Label("Menu bar monitor with realtime alerts", systemImage: "rays")
            }
            .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView: View {
    @StateObject private var scanner = DiskScanner()
    @ObservedObject private var monitor = SystemMonitor.shared
    @State private var screen: DiskScreen? = .overview

    var body: some View {
        VStack(spacing: 0) {
            TopBar(scanner: scanner)
            Divider()
            NavigationSplitView {
                List(selection: $screen) {
                    Section("Analyze") {
                        ForEach([DiskScreen.overview, .spaceLens, .large, .old, .duplicates, .junk]) { s in
                            Label(s.rawValue, systemImage: s.icon)
                                .tag(s)
                        }
                    }
                    Section("Optimize") {
                        ForEach([DiskScreen.unusedApps, .memory, .cleaner]) { s in
                            Label(s.rawValue, systemImage: s.icon)
                                .tag(s)
                        }
                    }
                    Section("Help") {
                        ForEach([DiskScreen.about]) { s in
                            Label(s.rawValue, systemImage: s.icon)
                                .tag(s)
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            } detail: {
                switch screen ?? .overview {
                case .overview:   OverviewView(scanner: scanner)
                case .spaceLens:  SpaceLensView(scanner: scanner)
                case .large:      LargeFilesView(scanner: scanner)
                case .old:        OldFilesView(scanner: scanner)
                case .duplicates: DuplicatesView(scanner: scanner)
                case .junk:       JunkView(scanner: scanner)
                case .unusedApps: UnusedAppsView(scanner: scanner)
                case .memory:     MemoryView(scanner: scanner)
                case .cleaner:    CleanerView(scanner: scanner)
                case .about:      AboutView()
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .overlay { ActionOverlay(scanner: scanner) }
        .alert("Disk Store Alert", isPresented: Binding(
            get: { monitor.alertMessage != nil },
            set: { if !$0 { monitor.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { monitor.alertMessage = nil }
        } message: {
            Text(monitor.alertMessage ?? "")
        }
        .task {
            if scanner.rootURL == nil {
                scanner.scan(url: FileManager.default.homeDirectoryForCurrentUser)
            }
            scanner.refreshCleanerData()
            scanner.refreshMemory()
        }
    }
}