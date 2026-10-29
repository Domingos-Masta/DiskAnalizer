// MARK: - System Monitor

import AppKit
import Combine
import Darwin
import Foundation
import UserNotifications

/// Realtime system monitor: samples disk, memory, and CPU usage, posts
/// notifications when thresholds are crossed, and drives the menu bar icon.
@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var isMonitoring = false
    @Published var menuBarEnabled = true {
        didSet {
            if oldValue != menuBarEnabled {
                onMenuBarEnabledChanged?(menuBarEnabled)
            }
        }
    }

    @Published var diskFreeBytes: Int64 = 0
    @Published var diskTotalBytes: Int64 = 0
    @Published var diskUsageFraction: Double = 0

    @Published var memoryPressure = 1
    @Published var memoryPressureLabel = "Normal"
    @Published var memoryFreeBytes: Int64 = 0

    @Published var cpuUsage: Double = 0

    @Published var alertMessage: String?

    var onMenuBarEnabledChanged: (@MainActor (Bool) -> Void)?

    private var monitorTask: Task<Void, Never>?
    private var lastCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var lastAlert: (kind: String, date: Date)?
    private var didRequestNotificationPermission = false

    private let sampleInterval: UInt64 = 10_000_000_000 // 10 s

    func start() {
        guard monitorTask == nil else { return }
        isMonitoring = true
        requestNotificationPermissionIfNeeded()
        sample()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.sampleInterval ?? 10_000_000_000)
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
    }

    // MARK: Sampling

    private func sample() {
        let disk = Self.diskFreeSpace()
        diskFreeBytes = disk.free
        diskTotalBytes = disk.total
        diskUsageFraction = disk.usage

        let stats = DiskScanner.readMemoryStats()
        memoryPressure = stats.pressureLevel
        memoryPressureLabel = stats.pressureLabel
        memoryFreeBytes = stats.freeBytes

        cpuUsage = Self.cpuUsage(previous: &lastCPUTicks)
        evaluateAlerts()
    }

    private func evaluateAlerts() {
        let now = Date()
        let cooldown: TimeInterval = 5 * 60

        func raise(_ kind: String, _ message: String) {
            if let last = lastAlert, last.kind == kind, now.timeIntervalSince(last.date) < cooldown {
                return
            }
            lastAlert = (kind, now)
            alertMessage = message
            postNotification(title: "Disk Store Alert", body: message)
        }

        if diskTotalBytes > 0 && diskUsageFraction >= 0.90 {
            raise("disk", "Disk almost full: \(Int(diskUsageFraction * 100))% used.")
        }
        if memoryPressure >= 4 {
            raise("memory", "Memory critically low.")
        } else if memoryPressure >= 2 && cpuUsage >= 0.85 {
            raise("resources", "High resource consumption: CPU \(Int(cpuUsage * 100))% and elevated memory pressure.")
        } else if cpuUsage >= 0.85 {
            raise("cpu", "High CPU usage: \(Int(cpuUsage * 100))%.")
        }
    }

    // MARK: Notifications

    private func requestNotificationPermissionIfNeeded() {
        guard !didRequestNotificationPermission, Bundle.main.bundleIdentifier != nil else { return }
        didRequestNotificationPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Static samplers

    nonisolated static func diskFreeSpace() -> (free: Int64, total: Int64, usage: Double) {
        let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        )
        let free = Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let usage: Double
        if total > 0 {
            usage = min(1.0, max(0.0, 1.0 - Double(free) / Double(total)))
        } else {
            usage = 0
        }
        return (free, total, usage)
    }

    nonisolated static func cpuUsage(
        previous: inout (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    ) -> Double {
        var load = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }

        let ticks = load.cpu_ticks
        let current = (user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)
        defer { previous = current }

        guard let prev = previous else { return 0 }
        let userDelta = UInt64(current.user &- prev.user)
        let systemDelta = UInt64(current.system &- prev.system)
        let niceDelta = UInt64(current.nice &- prev.nice)
        let idleDelta = UInt64(current.idle &- prev.idle)
        let totalDelta = userDelta + systemDelta + niceDelta + idleDelta
        guard totalDelta > 0 else { return 0 }

        let busy = userDelta + systemDelta + niceDelta
        return min(1.0, Double(busy) / Double(totalDelta))
    }
}

// MARK: - Menu bar icon

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let monitor: SystemMonitor
    private let onOpen: @MainActor () -> Void

    init(monitor: SystemMonitor, onOpen: @escaping @MainActor () -> Void) {
        self.monitor = monitor
        self.onOpen = onOpen
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rays", accessibilityDescription: "Disk Store Monitor")
        }
        statusItem.isVisible = monitor.menuBarEnabled

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        monitor.onMenuBarEnabledChanged = { [weak self] enabled in
            self?.statusItem.isVisible = enabled
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        addItem(menu, title: "Disk: \(monitor.diskFreeBytes.formattedBytes) free of \(monitor.diskTotalBytes.formattedBytes)", action: nil, key: "")
        addItem(menu, title: "Memory: \(monitor.memoryPressureLabel)", action: nil, key: "")
        addItem(menu, title: "CPU: \(Int(monitor.cpuUsage * 100))%", action: nil, key: "")

        menu.addItem(.separator())
        addItem(menu, title: "Open Disk Store", action: #selector(openApp), key: "o")
        addItem(menu, title: monitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                action: #selector(toggleMonitoring), key: "")

        menu.addItem(.separator())
        addItem(menu, title: "Quit Disk Store", action: #selector(quit), key: "q")
    }

    private func addItem(_ menu: NSMenu, title: String, action: Selector?, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func openApp() {
        onOpen()
    }

    @objc private func toggleMonitoring() {
        if monitor.isMonitoring {
            monitor.stop()
        } else {
            monitor.start()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
