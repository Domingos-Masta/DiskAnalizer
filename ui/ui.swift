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
                Text(file.folder).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Large Files").font(.largeTitle.bold())
                Spacer()
                if !scanner.largeFiles.isEmpty {
                    Text("\(scanner.largeFiles.count) files")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)

            if scanner.largeFiles.isEmpty {
                EmptyState(text: "No large files found in the scanned folder.")
            } else {
                List(scanner.largeFiles) { file in
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
                            Text(file.folder).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
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
                Text("Junk & Caches").font(.largeTitle.bold())
                Text("Caches, logs, trash and Xcode build artifacts. Moving these to Trash is usually safe.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)

            if scanner.junkFolders.isEmpty {
                EmptyState(text: "No known junk folders found.")
            } else {
                List(scanner.junkFolders) { folder in
                    HStack(spacing: 12) {
                        Image(systemName: "trash.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.url.lastPathComponent).font(.body.weight(.medium))
                            Text(folder.url.displayPath).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(folder.size.formattedBytes)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                        } label: { Image(systemName: "magnifyingglass.circle") }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            scanner.trash([folder.url]) { scanner.removeJunkFolder(folder.url) }
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
            }
            .listStyle(.inset)
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
                        ForEach([DiskScreen.overview, .large, .old, .duplicates, .junk]) { s in
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