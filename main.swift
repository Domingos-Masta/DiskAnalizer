// main.swift — Disk Store: a small disk-space analyzer for macOS
// Build app bundle:  ./build.sh        (output: build/DiskStore.app)
// Build plain binary: swiftc -O main.swift app/app.swift app/cleaner.swift \
//                     app/monitor.swift app/optimizer.swift helpers/helpers.swift \
//                     models/models.swift ui/ui.swift -o DiskStore
// Requires macOS 13+ and Xcode Command Line Tools.

import AppKit
import Foundation
import SwiftUI

// MARK: - App bootstrap
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        applyAppIcon()
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1150, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = "Disk Store"
        w.contentView = NSHostingView(rootView: ContentView())
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        self.window = w

        statusBar = StatusBarController(monitor: .shared) { [weak self] in
            self?.showWindow()
        }
        SystemMonitor.shared.start()
        DailyCleaner.shared.start()
        activateApp()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        // Keep running in the background. If the menu bar monitor is visible,
        // drop the Dock icon and live in the tray; otherwise keep the Dock icon
        // so the app can still be reopened.
        if SystemMonitor.shared.menuBarEnabled {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @MainActor
    private func applyAppIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApp.applicationIconImage = icon
    }

    @MainActor
    private func showWindow() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        activateApp()
    }

    @MainActor
    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor
    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Disk Store",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Disk Store",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()