// MARK: - Scanner

import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation

@MainActor
final class DiskScanner: ObservableObject {
    @Published var isScanning = false
    @Published var phase: ScanPhase = .idle
    @Published var progress: Double = 0
    @Published var rootURL: URL?
    @Published var totalSize: Int64 = 0
    @Published var fileCount = 0
    @Published var folderCount = 0
    @Published var topFolders: [FolderSize] = []
    @Published var largeFiles: [FileEntry] = []
    @Published var oldFiles: [FileEntry] = []
    @Published var duplicates: [DuplicateGroup] = []
    @Published var junkFolders: [FolderSize] = []
    @Published var duplicateWasted: Int64 = 0

    // MARK: Cleaner state
    @Published var unusedApps: [UnusedApp] = []
    @Published var leftovers: [LeftoverItem] = []
    @Published var trashSize: Int64 = 0
    @Published var isRefreshingCleaner = false

    // MARK: Memory state
    @Published var memoryApps: [MemoryApp] = []
    @Published var memoryStats: MemoryStats?

    // MARK: Action progress
    @Published var isPerformingAction = false
    @Published var actionMessage = ""
    @Published var actionProgress: Double = 0
    @Published var actionNotice: String?

    private var token: CancelToken?

    func cancel() { token?.cancel() }

    func scan(url: URL) {
        guard !isScanning else { return }
        isScanning = true
        phase = .listing
        progress = 0
        totalSize = 0
        fileCount = 0
        folderCount = 0
        topFolders = []
        largeFiles = []
        oldFiles = []
        duplicates = []
        junkFolders = []
        duplicateWasted = 0
        rootURL = url

        let token = CancelToken()
        self.token = token

        Task.detached(priority: .userInitiated) {
            let result = Self.performFullScan(
                url: url,
                token: token,
                progress: { p, ph in
                    Task { @MainActor [weak self] in
                        self?.progress = p
                        self?.phase = ph
                    }
                }
            )

            await MainActor.run { [weak self] in
                self?.apply(result)
            }
        }
    }

    private func apply(_ result: ScanResult) {
        totalSize = result.total
        fileCount = result.fileCount
        folderCount = result.folderCount
        topFolders = result.topFolders
        largeFiles = result.largeFiles
        oldFiles = result.oldFiles
        duplicates = result.duplicates
        junkFolders = result.junkFolders
        duplicateWasted = result.duplicateWasted
        isScanning = false
        phase = .done
        progress = 1
    }

    // MARK: Mutations after deletion

    func removeFile(_ url: URL) {
        largeFiles.removeAll { $0.url == url }
        oldFiles.removeAll { $0.url == url }
        duplicates = duplicates.compactMap { g in
            let remaining = g.files.filter { $0.url != url }
            return remaining.count > 1 ? DuplicateGroup(fileSize: g.fileSize, files: remaining) : nil
        }
        duplicateWasted = duplicates.reduce(0) { $0 + $1.wastedBytes }
    }

    func removeJunkFolder(_ url: URL) {
        junkFolders.removeAll { $0.url == url }
    }

    // MARK: Cleaner actions

    func refreshCleanerData() {
        guard !isRefreshingCleaner else { return }
        isRefreshingCleaner = true
        Task.detached(priority: .utility) {
            let apps = Self.detectUnusedApps()
            let leftovers = Self.detectLeftovers()
            let trash = Self.folderSize(
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            ) ?? 0

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.unusedApps = apps
                self.leftovers = leftovers
                self.trashSize = trash
                self.isRefreshingCleaner = false
            }
        }
    }

    func refreshMemory() {
        memoryStats = Self.readMemoryStats()
        memoryApps = Self.topMemoryApps()
    }

    func freeRAM() {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        actionMessage = "Freeing inactive memory…"
        actionProgress = 0

        Task.detached(priority: .userInitiated) {
            let message = Self.purgeInactiveMemory().message
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isPerformingAction = false
                self.actionMessage = ""
                self.actionNotice = message
                self.refreshMemory()
            }
        }
    }

    func emptyTrash() {
        guard !isPerformingAction else { return }
        let fm = FileManager.default
        let trashURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let items = (try? fm.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        guard !items.isEmpty else {
            trashSize = 0
            actionNotice = "Trash is already empty."
            return
        }

        isPerformingAction = true
        actionMessage = "Emptying Trash…"
        actionProgress = 0

        Task.detached(priority: .userInitiated) {
            let total = items.count
            for (index, item) in items.enumerated() {
                try? FileManager.default.removeItem(at: item)
                if index % 10 == 0 || index == total - 1 {
                    let progress = Double(index + 1) / Double(total)
                    await MainActor.run { [weak self] in
                        self?.actionProgress = progress
                    }
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.trashSize = 0
                self.isPerformingAction = false
                self.actionMessage = ""
                self.actionNotice = "Trash emptied."
            }
        }
    }

    func cleanLeftovers() {
        let items = leftovers
        guard !items.isEmpty, !isPerformingAction else { return }
        let ids = Set(items.map(\.id))
        trash(items.map(\.url), message: "Cleaning leftovers…") { [weak self] in
            guard let self else { return }
            self.leftovers.removeAll { ids.contains($0.id) }
            self.actionNotice = "Leftovers moved to Trash."
        }
    }

    func deleteLeftover(_ item: LeftoverItem) {
        trash([item.url], message: "Moving \(item.name) to Trash…") { [weak self] in
            self?.leftovers.removeAll { $0.id == item.id }
        }
    }

    func uninstallApp(_ app: UnusedApp) {
        trash([app.url], message: "Moving \(app.name) to Trash…") { [weak self] in
            self?.unusedApps.removeAll { $0.id == app.id }
        }
    }

    /// Moves files to the Trash and reports completion on the main actor.
    func trash(_ urls: [URL], message: String = "Moving to Trash…", onCompletion: @escaping @MainActor () -> Void = {}) {
        guard !urls.isEmpty, !isPerformingAction else { return }
        isPerformingAction = true
        actionMessage = message
        actionProgress = 0

        NSWorkspace.shared.recycle(urls) { _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPerformingAction = false
                self.actionMessage = ""
                self.actionProgress = 1
                onCompletion()
            }
        }
    }

    // MARK: Scan implementation (background)

    nonisolated static func performFullScan(
        url: URL,
        token: CancelToken,
        progress: @escaping (Double, ScanPhase) -> Void
    ) -> ScanResult {
        let keys: [URLResourceKey] = [
            .fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey,
            .isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey,
            .contentAccessDateKey
        ]
        let fm = FileManager.default
        let rootPath = url.path

        var folderSizes: [String: Int64] = [rootPath: 0]
        var total: Int64 = 0
        var fileCount = 0
        var folderCount = 0
        var fileEntries: [FileEntry] = []

        let dupThreshold: Int64 = 100 * 1024           // keep >= 100 KB
        let oldCutoff = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()

        progress(0.02, .listing)

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return ScanResult(total: 0, fileCount: 0, folderCount: 0,
                              topFolders: [], largeFiles: [], oldFiles: [],
                              duplicates: [], junkFolders: [], duplicateWasted: 0)
        }

        var counter = 0
        while let fileURL = enumerator.nextObject() as? URL {
            counter += 1
            if counter % 100 == 0 {
                if token.isCancelled { break }
                let p = min(0.5, 0.02 + 0.48 * Double(counter) / 200_000.0)
                progress(p, .listing)
            }

            guard let rv = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if rv.isSymbolicLink == true { continue }

            if rv.isDirectory == true {
                folderCount += 1
                continue
            }
            guard rv.isRegularFile == true else { continue }

            let size = Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
            if size == 0 { continue }

            let mod = rv.contentModificationDate ?? .distantPast
            let acc = rv.contentAccessDate ?? mod

            total += size
            fileCount += 1

            // Bubble size up through all ancestor folders up to root
            folderSizes[rootPath, default: 0] += size
            var parent = fileURL.deletingLastPathComponent()
            while parent.path != rootPath, parent.path.hasPrefix(rootPath + "/") {
                folderSizes[parent.path, default: 0] += size
                parent = parent.deletingLastPathComponent()
            }

            if size >= dupThreshold || acc < oldCutoff {
                fileEntries.append(FileEntry(url: fileURL, size: size, modified: mod, accessed: acc))
            }
        }

        progress(0.55, .hashing)

        let topFolders = folderSizes
            .filter { $0.key != rootPath }
            .map { FolderSize(url: URL(fileURLWithPath: $0.key), size: $0.value) }
            .sorted { $0.size > $1.size }

        let sortedBySize = fileEntries.sorted { $0.size > $1.size }
        let largeFiles = Array(sortedBySize.prefix(300))
        let oldFiles = Array(
            fileEntries.filter { $0.accessed < oldCutoff }
                .sorted { $0.size > $1.size }
                .prefix(300)
        )

        // Duplicate detection (files >= 1 MB, grouped by size then hashed)
        let candidates = fileEntries.filter { $0.size >= 1_000_000 }
        var bySize: [Int64: [FileEntry]] = [:]
        for f in candidates { bySize[f.size, default: []].append(f) }
        let sizeGroups = bySize.filter { $0.value.count > 1 }
        var dupes: [DuplicateGroup] = []
        var processed = 0
        let totalGroups = max(1, sizeGroups.count)

        for (size, group) in sizeGroups {
            if token.isCancelled { break }
            var byHash: [String: [FileEntry]] = [:]
            for f in group {
                if let h = try? sha256(of: f.url) {
                    byHash[h, default: []].append(f)
                }
            }
            for (_, sameFiles) in byHash where sameFiles.count > 1 {
                dupes.append(DuplicateGroup(fileSize: size, files: sameFiles))
            }
            processed += 1
            progress(0.55 + 0.4 * Double(processed) / Double(totalGroups), .hashing)
        }
        dupes.sort { $0.wastedBytes > $1.wastedBytes }
        let dupWasted = dupes.reduce(Int64(0)) { $0 + $1.wastedBytes }

        let junk = detectJunk()
        progress(1.0, .done)

        return ScanResult(
            total: total,
            fileCount: fileCount,
            folderCount: folderCount,
            topFolders: Array(topFolders.prefix(50)),
            largeFiles: largeFiles,
            oldFiles: oldFiles,
            duplicates: dupes,
            junkFolders: junk,
            duplicateWasted: dupWasted
        )
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = autoreleasepool {
                handle.readData(ofLength: 4 * 1024 * 1024)
            }
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func detectJunk() -> [FolderSize] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates: [URL] = [
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Logs"),
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
        ]
        var out: [FolderSize] = []
        for u in candidates {
            guard fm.fileExists(atPath: u.path) else { continue }
            if let s = folderSize(u), s > 0 {
                out.append(FolderSize(url: u, size: s))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    nonisolated static func folderSize(_ url: URL) -> Int64? {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return nil }
        var total: Int64 = 0
        while let u = en.nextObject() as? URL {
            autoreleasepool {
                if let rv = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
                    total += Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
                }
            }
        }
        return total
    }

    // MARK: Cleaner helpers (background)

    nonisolated static func normalizedKey(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return String(string.lowercased().unicodeScalars.filter { allowed.contains($0) })
    }

    nonisolated static func installedAppKeys() -> Set<String> {
        let fm = FileManager.default
        let dirs: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        var keys = Set<String>()
        for dir in dirs {
            let items = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for item in items where item.pathExtension == "app" {
                let nameKey = normalizedKey(item.deletingPathExtension().lastPathComponent)
                if !nameKey.isEmpty { keys.insert(nameKey) }
                if let bundleID = Bundle(url: item)?.bundleIdentifier {
                    let bundleKey = normalizedKey(bundleID)
                    if !bundleKey.isEmpty { keys.insert(bundleKey) }
                    if let component = bundleID.split(separator: ".").last {
                        let componentKey = normalizedKey(String(component))
                        if !componentKey.isEmpty { keys.insert(componentKey) }
                    }
                }
            }
        }
        return keys
    }

    nonisolated static func detectUnusedApps() -> [UnusedApp] {
        let fm = FileManager.default
        let dirs: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        let cutoff = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        var out: [UnusedApp] = []
        for dir in dirs {
            let items = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentAccessDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for item in items where item.pathExtension == "app" {
                let rv = try? item.resourceValues(forKeys: [.contentAccessDateKey])
                let lastUsed = rv?.contentAccessDate ?? .distantPast
                guard lastUsed < cutoff else { continue }
                let size = folderSize(item) ?? 0
                out.append(UnusedApp(
                    name: item.deletingPathExtension().lastPathComponent,
                    url: item,
                    size: size,
                    lastUsed: lastUsed == .distantPast ? nil : lastUsed
                ))
            }
        }
        return out.sorted {
            ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast)
        }
    }

    nonisolated static func detectLeftovers() -> [LeftoverItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let locations: [(String, URL)] = [
            ("Application Support", home.appendingPathComponent("Library/Application Support")),
            ("Caches", home.appendingPathComponent("Library/Caches")),
            ("Preferences", home.appendingPathComponent("Library/Preferences")),
            ("Logs", home.appendingPathComponent("Library/Logs")),
            ("Containers", home.appendingPathComponent("Library/Containers")),
            ("Group Containers", home.appendingPathComponent("Library/Group Containers")),
        ]
        let installed = installedAppKeys()
        let bundlePrefixes = ["com.", "org.", "net.", "io.", "dev.", "app.", "me.", "co."]

        var out: [LeftoverItem] = []
        for (location, dir) in locations {
            guard fm.fileExists(atPath: dir.path) else { continue }
            let items = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for item in items {
                let rawName = item.lastPathComponent
                let lower = rawName.lowercased()
                if location == "Preferences" && item.pathExtension != "plist" { continue }

                guard bundlePrefixes.contains(where: { lower.hasPrefix($0) }) else { continue }

                let key = normalizedKey(lower)
                guard key.count >= 6, !key.hasPrefix("comapple") else { continue }

                let matchesInstalled = installed.contains(key) || installed.contains { candidate in
                    (candidate.count >= 5 && key.hasPrefix(candidate))
                        || (key.count >= 5 && candidate.hasPrefix(key))
                }
                if matchesInstalled { continue }

                let rv = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let size: Int64
                if rv?.isDirectory == true {
                    size = folderSize(item) ?? 0
                } else {
                    size = Int64(rv?.fileSize ?? 0)
                }
                out.append(LeftoverItem(name: rawName, url: item, size: size, location: location))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    // MARK: Memory helpers

    nonisolated static func readMemoryStats() -> MemoryStats {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return MemoryStats(totalBytes: total, freeBytes: 0, activeBytes: 0, inactiveBytes: 0,
                               wiredBytes: 0, compressedBytes: 0, cachedBytes: 0,
                               pressureLevel: pressureLevel())
        }
        let pageSize = Int64(getpagesize())
        return MemoryStats(
            totalBytes: total,
            freeBytes: Int64(stats.free_count) * pageSize,
            activeBytes: Int64(stats.active_count) * pageSize,
            inactiveBytes: Int64(stats.inactive_count) * pageSize,
            wiredBytes: Int64(stats.wire_count) * pageSize,
            compressedBytes: Int64(stats.compressor_page_count) * pageSize,
            cachedBytes: (Int64(stats.external_page_count) + Int64(stats.purgeable_count)) * pageSize,
            pressureLevel: pressureLevel()
        )
    }

    nonisolated static func pressureLevel() -> Int {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 1 }
        return Int(level)
    }

    static func topMemoryApps(limit: Int = 5) -> [MemoryApp] {
        var apps: [MemoryApp] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) > 0, info.pti_resident_size > 0 else { continue }
            apps.append(MemoryApp(
                name: app.localizedName ?? "Unknown",
                pid: pid,
                memoryBytes: Int64(info.pti_resident_size)
            ))
        }
        return Array(apps.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
    }

    nonisolated static func purgeInactiveMemory() -> (success: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0 {
                return (true, "Inactive memory released.")
            }
            return (false, output.isEmpty
                ? "Could not release memory (requires administrator privileges)."
                : output)
        } catch {
            return (false, "Could not run purge: \(error.localizedDescription)")
        }
    }
}