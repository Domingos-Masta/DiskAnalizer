// MARK: - Models

import Foundation

enum FileCategory: String, CaseIterable, Sendable {
    case sql = "SQL Dump"
    case media = "Media"
    case archive = "Archive"
    case image = "Disk Image"
    case document = "Document"
    case app = "Application"
    case other = "Other"
}

struct FileEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date
    let accessed: Date
    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().displayPath }

    var category: FileCategory {
        switch url.pathExtension.lowercased() {
        case "sql", "sqlite", "db", "dump", "sql.gz":
            return .sql
        case "mov", "mp4", "m4v", "avi", "mkv", "webm",
             "mp3", "wav", "aiff", "m4a", "flac", "aac":
            return .media
        case "zip", "tar", "gz", "bz2", "7z", "rar", "tgz", "xz":
            return .archive
        case "dmg", "iso", "img":
            return .image
        case "doc", "docx", "pdf", "pages", "numbers", "key",
             "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md":
            return .document
        case "app":
            return .app
        default:
            return .other
        }
    }
}

struct FolderSize: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
}

struct SpaceNode: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    let isDirectory: Bool

    var category: FileCategory {
        switch url.pathExtension.lowercased() {
        case "sql", "sqlite", "db", "dump", "sql.gz":
            return .sql
        case "mov", "mp4", "m4v", "avi", "mkv", "webm",
             "mp3", "wav", "aiff", "m4a", "flac", "aac":
            return .media
        case "zip", "tar", "gz", "bz2", "7z", "rar", "tgz", "xz":
            return .archive
        case "dmg", "iso", "img":
            return .image
        case "doc", "docx", "pdf", "pages", "numbers", "key",
             "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md":
            return .document
        case "app":
            return .app
        default:
            return .other
        }
    }
}

enum JunkCategory: String, Sendable {
    case caches = "User Caches"
    case logs = "Logs"
    case xcode = "Xcode"
    case softwareUpdate = "Software Update"
    case mail = "Mail Downloads"
    case universal = "Universal Binary"
}

struct JunkItem: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    let category: JunkCategory
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
    let junkItems: [JunkItem]
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

// MARK: - Optimization module

enum LaunchAgentScope: String, Sendable {
    case user = "User"
    case system = "System"
}

struct LaunchAgentItem: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let url: URL
    let scope: LaunchAgentScope
    let program: String
    let runAtLoad: Bool
    var disabled: Bool
}

struct LoginItem: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    var enabled: Bool
}

struct RunningProcess: Identifiable, Sendable {
    let id = UUID()
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memoryBytes: Int64
    let isApplication: Bool
}

struct FrozenApp: Identifiable, Sendable {
    let id = UUID()
    let pid: Int32
    let name: String
}

enum MaintenanceTask: String, CaseIterable, Identifiable, Sendable {
    case freeRAM = "Free Up RAM"
    case purgeDiskSpace = "Purge Purgeable Disk Space"
    case reindexSpotlight = "Reindex Spotlight"
    case repairPermissions = "Repair Disk & Folder Permissions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .freeRAM:           return "memorychip"
        case .purgeDiskSpace:    return "externaldrive.badge.minus"
        case .reindexSpotlight:  return "magnifyingglass"
        case .repairPermissions: return "lock.shield"
        }
    }

    var detail: String {
        switch self {
        case .freeRAM:
            return "Runs purge to release inactive memory."
        case .purgeDiskSpace:
            return "Thins local Time Machine snapshots to reclaim purgeable space."
        case .reindexSpotlight:
            return "Erases and rebuilds the Spotlight index."
        case .repairPermissions:
            return "Resets permissions on the current user's home folder."
        }
    }
}

struct MaintenanceLogEntry: Identifiable, Sendable {
    let id = UUID()
    let task: MaintenanceTask
    let success: Bool
    let message: String
    let date: Date
}
