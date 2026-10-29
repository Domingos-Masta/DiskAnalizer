// MARK: - Daily Cleaner

import Foundation

struct CleanFlags: Sendable {
    let emptyTrash: Bool
    let leftovers: Bool
    let caches: Bool
    let logs: Bool
}

/// Schedules and runs the configured cleaning actions once per day.
@MainActor
final class DailyCleaner: ObservableObject {
    static let shared = DailyCleaner()

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }
    @Published var hour: Int {
        didSet { defaults.set(hour, forKey: Key.hour) }
    }
    @Published var emptyTrashEnabled: Bool {
        didSet { defaults.set(emptyTrashEnabled, forKey: Key.emptyTrash) }
    }
    @Published var cleanLeftoversEnabled: Bool {
        didSet { defaults.set(cleanLeftoversEnabled, forKey: Key.cleanLeftovers) }
    }
    @Published var clearCachesEnabled: Bool {
        didSet { defaults.set(clearCachesEnabled, forKey: Key.clearCaches) }
    }
    @Published var clearLogsEnabled: Bool {
        didSet { defaults.set(clearLogsEnabled, forKey: Key.clearLogs) }
    }
    @Published var lastCleanDate: Date?
    @Published var lastCleanSummary: String?
    @Published var isCleaning = false

    private let defaults = UserDefaults.standard
    private var schedulerTask: Task<Void, Never>?

    private enum Key {
        static let enabled = "DailyClean.enabled"
        static let hour = "DailyClean.hour"
        static let emptyTrash = "DailyClean.emptyTrash"
        static let cleanLeftovers = "DailyClean.cleanLeftovers"
        static let clearCaches = "DailyClean.clearCaches"
        static let clearLogs = "DailyClean.clearLogs"
        static let lastCleanDate = "DailyClean.lastCleanDate"
        static let lastCleanSummary = "DailyClean.lastCleanSummary"
    }

    init() {
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? false
        hour = defaults.object(forKey: Key.hour) as? Int ?? 10
        emptyTrashEnabled = defaults.object(forKey: Key.emptyTrash) as? Bool ?? true
        cleanLeftoversEnabled = defaults.object(forKey: Key.cleanLeftovers) as? Bool ?? true
        clearCachesEnabled = defaults.object(forKey: Key.clearCaches) as? Bool ?? false
        clearLogsEnabled = defaults.object(forKey: Key.clearLogs) as? Bool ?? false
        lastCleanDate = defaults.object(forKey: Key.lastCleanDate) as? Date
        lastCleanSummary = defaults.string(forKey: Key.lastCleanSummary)
    }

    /// Starts the background scheduler. Safe to call more than once.
    func start() {
        guard schedulerTask == nil else { return }
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    /// Checks whether the daily clean is due and runs it if so.
    func tick() {
        guard enabled, !isCleaning else { return }
        let now = Date()
        let calendar = Calendar.current
        if let last = lastCleanDate, calendar.isDate(last, inSameDayAs: now) { return }
        guard calendar.component(.hour, from: now) >= hour else { return }
        runDailyClean()
    }

    func runDailyClean() {
        guard !isCleaning else { return }
        isCleaning = true
        let flags = CleanFlags(
            emptyTrash: emptyTrashEnabled,
            leftovers: cleanLeftoversEnabled,
            caches: clearCachesEnabled,
            logs: clearLogsEnabled
        )

        Task.detached(priority: .utility) {
            let summary = DailyCleaner.perform(flags: flags)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isCleaning = false
                self.lastCleanDate = Date()
                self.lastCleanSummary = summary
                self.defaults.set(self.lastCleanDate, forKey: Key.lastCleanDate)
                self.defaults.set(summary, forKey: Key.lastCleanSummary)
            }
        }
    }

    // MARK: Cleaning implementation

    nonisolated static func perform(flags: CleanFlags) -> String {
        let fm = FileManager.default
        var parts: [String] = []

        if flags.emptyTrash {
            let trash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            let items = (try? fm.contentsOfDirectory(
                at: trash,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            var removed = 0
            for item in items where (try? fm.removeItem(at: item)) != nil {
                removed += 1
            }
            parts.append("Trash: \(removed) items")
        }

        if flags.leftovers {
            let leftovers = DiskScanner.detectLeftovers()
            var removed = 0
            for item in leftovers {
                var resultingURL: NSURL?
                do {
                    try fm.trashItem(at: item.url, resultingItemURL: &resultingURL)
                    removed += 1
                } catch {}
            }
            parts.append("Leftovers: \(removed) items")
        }

        if flags.caches {
            let caches = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
            parts.append("Caches: \(removeContents(of: caches, fm: fm)) items")
        }

        if flags.logs {
            let logs = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
            parts.append("Logs: \(removeContents(of: logs, fm: fm)) items")
        }

        return parts.isEmpty ? "No cleaning actions selected." : parts.joined(separator: " · ")
    }

    nonisolated static func removeContents(of directory: URL, fm: FileManager) -> Int {
        let items = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var removed = 0
        for item in items where (try? fm.removeItem(at: item)) != nil {
            removed += 1
        }
        return removed
    }
}
