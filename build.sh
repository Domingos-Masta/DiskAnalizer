#!/bin/bash
# Build Disk Store and package it as a macOS .app bundle.
#
# Usage: ./build.sh
# Output: build/DiskStore.app

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DiskStore"
BUNDLE_DIR="build"
BUNDLE="$BUNDLE_DIR/$APP_NAME.app"
CONTENTS="$BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

rm -rf "$BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# App icon (generated at project root; see AppIcon.icns).
if [[ -f "AppIcon.icns" ]]; then
    cp "AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Compile all sources into the bundle's executable.
swiftc -O \
    main.swift \
    app/app.swift \
    app/cleaner.swift \
    app/monitor.swift \
    helpers/helpers.swift \
    models/models.swift \
    ui/ui.swift \
    -o "$MACOS_DIR/$APP_NAME"

# Write the bundle's property list.
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Disk Store</string>
    <key>CFBundleExecutable</key>
    <string>DiskStore</string>
    <key>CFBundleIdentifier</key>
    <string>com.isysdcore.DiskStore</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Disk Store</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Traditional bundle marker file.
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Ad-hoc code sign so the app launches locally without a developer identity.
codesign --force --sign - "$BUNDLE"

echo "Built: $BUNDLE"
