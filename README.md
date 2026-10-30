# Disk Store

A lightweight macOS disk-space analyzer, system cleaner, and optimizer built with SwiftUI. It scans your drives to surface large files, duplicates, and junk, then helps you reclaim space — and it keeps working from the menu bar after you close the window.

## Features

- **Overview** — total disk usage, file/folder counts, largest folders, and duplicate waste.
- **Large Files** — find and remove the biggest files, with category badges (SQL dumps, media, archives, etc.) and filtering.
- **Unused Files** — files not accessed in 6+ months, with category badges.
- **Duplicates** — content-hashed (SHA-256) duplicate detection (files ≥ 1 MB).
- **Space Lens** — a CleanMyMac-style squarified treemap with hover inspection and breadcrumb navigation; click a folder to zoom in, click a file to reveal it in Finder.
- **System Junk** — user caches, logs, Xcode build artifacts, software update leftovers, mail downloads, and universal binaries.
- **Unused Apps** — apps not opened in 6+ months, with uninstall (move to Trash).
- **Memory** — memory stats, pressure level, top 5 apps by RAM, and a "Free Up RAM" action.
- **Cleaner** — user Trash + "Empty Trash"/"Empty All Bins" (all mounted disks), and leftovers left behind by uninstalled apps.
- **Optimization** — manage login items and launch agents, terminate heavy background consumers or frozen apps, and run maintenance tasks (free RAM, purge purgeable disk space, reindex Spotlight, repair disk/folder permissions).
- **Automatic daily cleaning** — schedules a daily run (while the app is open) to empty the Trash, clean leftovers, and optionally clear caches/logs. Configured from the Cleaner screen.
- **Menu bar monitor** — a `rays` status item showing disk/memory/CPU and quick actions; toggle it from the top bar.
- **Background tray operation** — closing the main window keeps the app running in the menu bar (the Dock icon is hidden while the menu bar monitor is enabled); reopen it from the tray.
- **Realtime alerts** — system notifications (plus in-app alerts) when the disk is almost full, memory is critically low, or CPU usage is high.

## Usage

### Starting the app

```bash
./build.sh
open build/DiskStore.app
```

On first launch the app scans your home folder automatically. Use **Choose Folder** in the top bar to scan a different location.

### Screens

The sidebar is split into Analyze, Optimize, and Help sections.

| Screen | What it does |
| --- | --- |
| **Overview** | Disk totals, file/folder counts, largest folders, and duplicate waste at a glance. |
| **Space Lens** | Squarified treemap of disk usage; zoom into folders and reveal files in Finder. |
| **Large Files** | Biggest files with category badges and a category filter. |
| **Unused Files** | Files not accessed in 6+ months, sorted by size. |
| **Duplicates** | Groups of identical files (by content hash) with wasted-space totals. |
| **Junk & Caches** | System and user junk: caches, logs, Xcode artifacts, software update leftovers, mail downloads, universal binaries. |
| **Unused Apps** | Apps not opened in 6+ months; move them to Trash. |
| **Memory** | RAM breakdown, pressure level, top apps by memory, and Free Up RAM. |
| **Cleaner** | Empty the user Trash or all bins, clean leftovers, and configure the daily automatic clean. |
| **Optimization** | Maintenance tasks, background processes, frozen apps, login items, and launch agents. |
| **About** | Version and feature summary. |

### Menu bar & background

- Closing the main window keeps the app running. While the menu bar monitor is enabled, the Dock icon is hidden and the app lives in the tray.
- Click the `rays` icon for disk/memory/CPU stats and quick actions (Open Disk Store, Start/Stop Monitoring, Quit).
- Toggle the menu bar monitor with the `rays` button in the top bar. If it is disabled, closing the window keeps the Dock icon so the app can still be reopened.

## Permissions

- **Automation (Apple Events)** — the Optimization screen reads and toggles **Login Items** and detects **Frozen Apps** through System Events. macOS prompts the first time; grant access under *System Settings → Privacy & Security → Automation*. If denied, those lists stay empty.
- **Administrator privileges** — the maintenance tasks (**Free Up RAM**, **Purge Purgeable Disk Space**, **Reindex Spotlight**, **Repair Disk & Folder Permissions**) prompt for an admin password and run elevated via `osascript ... with administrator privileges`. Cancel the prompt to skip a task.
- **File access** — the app reads files to compute sizes, so macOS may ask for access to protected folders (Desktop, Documents, Downloads) during scans.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`swiftc`)

## Build

```bash
./build.sh
```

This produces an ad-hoc signed app bundle at `build/DiskStore.app`.

## Run

```bash
open build/DiskStore.app
```

Or build and run a plain binary:

```bash
swiftc -O main.swift app/app.swift app/cleaner.swift app/monitor.swift app/optimizer.swift helpers/helpers.swift models/models.swift ui/ui.swift -o DiskStore
./DiskStore
```

## Architecture

| File | Responsibility |
| --- | --- |
| [main.swift](main.swift) | App bootstrap: `AppDelegate`, menu construction, window management, and the background/tray behavior. |
| [app/app.swift](app/app.swift) | `DiskScanner` — scanning, hashing, junk/leftover/unused-app detection, Trash and memory helpers. |
| [app/cleaner.swift](app/cleaner.swift) | `DailyCleaner` — the once-per-day cleaning scheduler and its actions. |
| [app/monitor.swift](app/monitor.swift) | `SystemMonitor` (disk/memory/CPU sampling and alerts) and `StatusBarController` (menu bar item). |
| [app/optimizer.swift](app/optimizer.swift) | `Optimizer` — login items, launch agents, process/frozen-app management, and maintenance tasks. |
| [helpers/helpers.swift](helpers/helpers.swift) | Byte/URL formatting helpers and `CancelToken`. |
| [models/models.swift](models/models.swift) | Data models shared across the app. |
| [ui/ui.swift](ui/ui.swift) | All SwiftUI views, including the `OptimizationView`. |
| [build.sh](build.sh) | Compiles the sources, assembles `DiskStore.app`, writes `Info.plist`, and ad-hoc code-signs it. |

## Notes

- **Leftover detection** is heuristic and conservative (bundle-id-style names only). Always review items before deleting.
- The app icon is `AppIcon.icns` at the project root and is copied into the bundle by `build.sh`.
- The bundle identifier is `com.isysdcore.DiskStore` — change it in `build.sh` if needed.

## License

MIT — see [LICENSE](LICENSE).
