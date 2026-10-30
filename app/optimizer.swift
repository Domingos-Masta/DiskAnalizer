// MARK: - Optimizer

import AppKit
import Darwin
import Foundation

/// Manages login items, launch agents, background processes, frozen apps,
/// and low-level maintenance routines (RAM purge, purgeable disk space,
/// Spotlight reindex, and permission repair).
@MainActor
final class Optimizer: ObservableObject {
    static let shared = Optimizer()

    @Published var launchAgents: [LaunchAgentItem] = []
    @Published var loginItems: [LoginItem] = []
    @Published var processes: [RunningProcess] = []
    @Published var frozenApps: [FrozenApp] = []
    @Published var isRefreshing = false
    @Published var activeMaintenanceTask: MaintenanceTask?
    @Published var maintenanceLog: [MaintenanceLogEntry] = []
    @Published var notice: String?

    // MARK: Refresh

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task.detached(priority: .utility) {
            let agents = Self.detectLaunchAgents()
            let login = Self.detectLoginItems()
            let procs = Self.detectProcesses()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.launchAgents = agents
                self.loginItems = login
                self.processes = procs
                self.isRefreshing = false
            }
        }
    }

    func detectFrozen() {
        Task.detached(priority: .utility) {
            let frozen = Self.detectFrozenApps()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.frozenApps = frozen
                if frozen.isEmpty { self.notice = "No frozen applications detected." }
            }
        }
    }

    // MARK: Actions

    func toggleLaunchAgent(_ item: LaunchAgentItem, enable: Bool) {
        guard item.disabled == enable else { return }
        Task.detached(priority: .userInitiated) {
            let result = Self.setLaunchAgent(item, enabled: enable)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if result.success {
                    if let index = self.launchAgents.firstIndex(where: { $0.id == item.id }) {
                        self.launchAgents[index].disabled = !enable
                    }
                }
                self.notice = result.message
            }
        }
    }

    func toggleLoginItem(_ item: LoginItem) {
        let enable = !item.enabled
        Task.detached(priority: .userInitiated) {
            let result = Self.setLoginItem(item, enabled: enable)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if result.success {
                    if let index = self.loginItems.firstIndex(where: { $0.id == item.id }) {
                        self.loginItems[index].enabled = enable
                    }
                }
                self.notice = result.message
            }
        }
    }

    func terminate(_ process: RunningProcess, force: Bool) {
        Task.detached(priority: .userInitiated) {
            let ok = Self.terminateProcess(pid: process.pid, force: force)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if ok {
                    self.processes.removeAll { $0.pid == process.pid }
                    self.frozenApps.removeAll { $0.pid == process.pid }
                    self.notice = "\(process.name) \(force ? "force quit" : "terminated")."
                } else {
                    self.notice = "Could not \(force ? "force quit" : "terminate") \(process.name)."
                }
            }
        }
    }

    func terminateFrozen(_ app: FrozenApp) {
        Task.detached(priority: .userInitiated) {
            let ok = Self.terminateProcess(pid: app.pid, force: true)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if ok {
                    self.frozenApps.removeAll { $0.pid == app.pid }
                    self.processes.removeAll { $0.pid == app.pid }
                    self.notice = "\(app.name) force quit."
                } else {
                    self.notice = "Could not force quit \(app.name)."
                }
            }
        }
    }

    func runMaintenance(_ task: MaintenanceTask) {
        guard activeMaintenanceTask == nil else { return }
        activeMaintenanceTask = task
        Task.detached(priority: .userInitiated) {
            let result = Self.performMaintenance(task)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.maintenanceLog.insert(
                    MaintenanceLogEntry(task: task, success: result.success,
                                       message: result.message, date: Date()),
                    at: 0
                )
                self.activeMaintenanceTask = nil
                self.notice = result.message
            }
        }
    }

    // MARK: Launch agent detection

    nonisolated static func detectLaunchAgents() -> [LaunchAgentItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates: [(LaunchAgentScope, URL)] = [
            (.user, home.appendingPathComponent("Library/LaunchAgents")),
            (.system, URL(fileURLWithPath: "/Library/LaunchAgents")),
            (.system, URL(fileURLWithPath: "/Library/LaunchDaemons")),
        ]

        var out: [LaunchAgentItem] = []
        for (scope, directory) in candidates {
            let urls = (try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls where url.pathExtension == "plist" {
                if let item = parseLaunchAgent(url, scope: scope) {
                    out.append(item)
                }
            }
        }
        return out.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    nonisolated static func parseLaunchAgent(_ url: URL, scope: LaunchAgentScope) -> LaunchAgentItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else { return nil }

        let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        let disabled = dict["Disabled"] as? Bool ?? false
        let runAtLoad = dict["RunAtLoad"] as? Bool ?? false

        let program: String
        if let arguments = dict["ProgramArguments"] as? [String], !arguments.isEmpty {
            program = arguments.joined(separator: " ")
        } else if let executable = dict["Program"] as? String {
            program = executable
        } else {
            program = ""
        }

        return LaunchAgentItem(
            label: label,
            url: url,
            scope: scope,
            program: program,
            runAtLoad: runAtLoad,
            disabled: disabled
        )
    }

    nonisolated static func setLaunchAgent(_ item: LaunchAgentItem, enabled: Bool) -> (success: Bool, message: String) {
        let uid = String(getuid())
        let domain = item.scope == .user ? "gui/\(uid)" : "system"
        let path = shellQuoted(item.url.path)
        let command: String
        if enabled {
            command = "/bin/launchctl enable \(domain)/\(item.label) 2>/dev/null; /bin/launchctl bootstrap \(domain) \(path) 2>/dev/null || true"
        } else {
            command = "/bin/launchctl bootout \(domain)/\(item.label) 2>/dev/null; /bin/launchctl disable \(domain)/\(item.label) 2>/dev/null || true"
        }

        let result = item.scope == .user
            ? runShellCommand(command)
            : runPrivilegedShell(command)
        if result.status == 0 {
            return (true, "\(item.label) \(enabled ? "enabled" : "disabled").")
        }
        return (false, result.output.isEmpty
            ? "Could not update \(item.label)."
            : result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Login item detection

    nonisolated static func detectLoginItems() -> [LoginItem] {
        let script = """
        tell application "System Events"
            set out to ""
            repeat with li in every login item
                set p to ""
                try
                    set p to path of li
                end try
                set out to out & (name of li) & "|" & p & linefeed
            end repeat
            return out
        end tell
        """
        let result = runAppleScript(script, timeout: 10)
        guard result.status == 0 else { return [] }

        var items: [LoginItem] = []
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            let name = parts.first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            let path = parts.count > 1
                ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            items.append(LoginItem(name: name, path: path, enabled: true))
        }
        return items
    }

    nonisolated static func setLoginItem(_ item: LoginItem, enabled: Bool) -> (success: Bool, message: String) {
        let name = appleScriptEscaped(item.name)
        let removeScript = """
        tell application "System Events"
            delete (every login item whose name is "\(name)")
            return "ok"
        end tell
        """
        _ = runAppleScript(removeScript, timeout: 15)

        guard enabled else { return (true, "\(item.name) disabled.") }
        guard !item.path.isEmpty else {
            return (false, "Could not re-enable \(item.name): no recorded path.")
        }

        let path = appleScriptEscaped(item.path)
        let addScript = """
        tell application "System Events"
            make new login item at end of login items with properties {path:"\(path)", hidden:false}
            return "ok"
        end tell
        """
        let result = runAppleScript(addScript, timeout: 15)
        if result.status == 0 {
            return (true, "\(item.name) enabled.")
        }
        return (false, result.output.isEmpty
            ? "Could not enable \(item.name)."
            : result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Process detection

    nonisolated static func detectProcesses() -> [RunningProcess] {
        let appPIDs = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map(\.processIdentifier))

        let result = runShell(executable: "/bin/ps",
                              arguments: ["-axo", "pid=,pcpu=,rss=,comm="])
        guard result.status == 0 else { return [] }

        var out: [RunningProcess] = []
        for line in result.output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKB = Int64(fields[2]) else { continue }
            let rawName = String(fields[3]).trimmingCharacters(in: .whitespaces)
            guard !rawName.isEmpty, pid > 0 else { continue }
            let name = (rawName as NSString).lastPathComponent
            out.append(RunningProcess(
                pid: pid,
                name: name,
                cpuPercent: cpu,
                memoryBytes: rssKB * 1024,
                isApplication: appPIDs.contains(pid)
            ))
        }
        return out.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    nonisolated static func detectFrozenApps() -> [FrozenApp] {
        let script = """
        tell application "System Events"
            set out to ""
            repeat with p in (every application process whose unresponsive is true)
                set out to out & (unix id of p) & "|" & (name of p) & linefeed
            end repeat
            return out
        end tell
        """
        let result = runAppleScript(script, timeout: 10)
        guard result.status == 0 else { return [] }

        var out: [FrozenApp] = []
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            guard let pid = parts.first.flatMap({ Int32($0.trimmingCharacters(in: .whitespaces)) }),
                  pid > 0 else { continue }
            let name = parts.count > 1
                ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                : "Process \(pid)"
            out.append(FrozenApp(pid: pid, name: name))
        }
        return out
    }

    nonisolated static func terminateProcess(pid: Int32, force: Bool) -> Bool {
        guard pid > 0 else { return false }
        return Darwin.kill(pid, force ? SIGKILL : SIGTERM) == 0
    }

    // MARK: Maintenance routines

    nonisolated static func performMaintenance(_ task: MaintenanceTask) -> (success: Bool, message: String) {
        let result: (status: Int32, output: String)
        let fallback: String

        switch task {
        case .freeRAM:
            fallback = "Inactive memory released."
            result = runPrivilegedShell("/usr/sbin/purge")
        case .purgeDiskSpace:
            fallback = "Purgeable disk space reclaimed."
            result = runPrivilegedShell("/usr/bin/tmutil thinlocalsnapshots / 999999999999 1")
        case .reindexSpotlight:
            fallback = "Spotlight reindexing started."
            result = runPrivilegedShell("/usr/bin/mdutil -E /")
        case .repairPermissions:
            fallback = "Disk and folder permissions repaired."
            result = runPrivilegedShell("/usr/sbin/diskutil resetUserPermissions / \(getuid())")
        }

        let message = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status == 0 {
            return (true, message.isEmpty ? fallback : message)
        }
        return (false, message.isEmpty ? "Task failed." : message)
    }

    // MARK: Shell helpers

    nonisolated static func runShell(executable: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = (String(data: outData, encoding: .utf8) ?? "")
            + (String(data: errData, encoding: .utf8) ?? "")
        return (process.terminationStatus, output)
    }

    nonisolated static func runShellCommand(_ command: String) -> (status: Int32, output: String) {
        runShell(executable: "/bin/sh", arguments: ["-c", command])
    }

    /// Runs `osascript -e` and waits for completion. When `timeout` is greater
    /// than zero the process is terminated if it does not finish in time, so a
    /// pending Automation/Apple Events permission prompt cannot block forever.
    nonisolated static func runAppleScript(_ source: String, timeout: TimeInterval = 0) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }

        if timeout > 0 {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Date() >= deadline {
                    process.terminate()
                    return (124, "The AppleScript request timed out.")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        } else {
            process.waitUntilExit()
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = (String(data: outData, encoding: .utf8) ?? "")
            + (String(data: errData, encoding: .utf8) ?? "")
        return (process.terminationStatus, output)
    }

    /// Runs a shell command with an administrator-privilege prompt.
    nonisolated static func runPrivilegedShell(_ command: String) -> (status: Int32, output: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        return runAppleScript(source)
    }

    nonisolated static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func appleScriptEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}