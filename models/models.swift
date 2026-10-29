// MARK: - Models

import Foundation

struct FileEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date
    let accessed: Date
    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().displayPath }
}

struct FolderSize: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let fileSize: Int64
    let files: [FileEntry]
    var wastedBytes: Int64 { fileSize * Int64(max(0, files.count - 1)) }
}

enum ScanPhase: String {
    case idle = "Ready"
    case listing = "Scanning files…"
    case hashing = "Detecting duplicates…"
    case done = "Done"
}

struct ScanResult {
    let total: Int64
    let fileCount: Int
    let folderCount: Int
    let topFolders: [FolderSize]
    let largeFiles: [FileEntry]
    let oldFiles: [FileEntry]
    let duplicates: [DuplicateGroup]
    let junkFolders: [FolderSize]
    let duplicateWasted: Int64
}

struct UnusedApp: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    let lastUsed: Date?
}

struct LeftoverItem: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    let location: String
}

struct MemoryApp: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let pid: Int32
    let memoryBytes: Int64
}

struct MemoryStats: Sendable {
    let totalBytes: Int64
    let freeBytes: Int64
    let activeBytes: Int64
    let inactiveBytes: Int64
    let wiredBytes: Int64
    let compressedBytes: Int64
    let cachedBytes: Int64
    let pressureLevel: Int

    var usedBytes: Int64 { activeBytes + wiredBytes + compressedBytes }
    var pressureLabel: String {
        switch pressureLevel {
        case 4: return "Critical"
        case 2: return "Warning"
        default: return "Normal"
        }
    }
}
