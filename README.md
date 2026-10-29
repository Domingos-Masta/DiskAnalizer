# Disk Store

A lightweight macOS disk-space analyzer and system cleaner built with SwiftUI.

## Features

- **Overview** — total disk usage, file/folder counts, largest folders, and duplicate waste.
- **Large Files** — find and remove the biggest files in the scanned folder.
- **Unused Files** — files not accessed in 6+ months.
- **Duplicates** — content-hashed duplicate detection (files ≥ 1 MB).
- **Junk & Caches** — caches, logs, and Xcode build artifacts.
- **Unused Apps** — apps not opened in 6+ months, with uninstall (move to Trash).
- **Memory** — memory stats, pressure level, top 5 apps by RAM, and a "Free Up RAM" action.
- **Cleaner** — user Trash size + "Empty Trash", and leftovers left behind by uninstalled apps.
- **Menu bar monitor** — a `rays` status item showing disk/memory/CPU and quick actions; toggle it from the top bar.
- **Realtime alerts** — system notifications (plus in-app alerts) when the disk is almost full, memory is critically low, or CPU usage is high.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`swiftc`)

## Build

```bash
./build.sh
```

This produces a signed app bundle at `build/DiskStore.app`.

## Run

```bash
open build/DiskStore.app
```

Or build and run a plain binary:

```bash
swiftc -O main.swift app/app.swift app/monitor.swift helpers/helpers.swift models/models.swift ui/ui.swift -o DiskStore
./DiskStore
```

## Notes

- **Free Up RAM** runs `/usr/sbin/purge`, which normally requires administrator privileges. The app reports the result if it is not permitted.
- **Leftover detection** is heuristic and conservative (bundle-id-style names only). Always review items before deleting.
- The app icon is generated as `AppIcon.icns` at the project root and is copied into the bundle by `build.sh`.
- The bundle identifier is `com.example.DiskStore` — change it in `build.sh` if needed.

## License

MIT — see [LICENSE](LICENSE).
