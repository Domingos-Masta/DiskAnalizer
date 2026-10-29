// MARK: - Helpers

import Foundation

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension URL {
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}