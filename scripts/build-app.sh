#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-env.sh"
output="${1:-$project_root/dist}"
mkdir -p "$output" "$build_root/slices"
output="$(cd "$output" && pwd)"

for architecture in arm64 x86_64; do
  target="$architecture-apple-macosx13.0"
  swift build "${swift_options[@]}" --triple "$target" -c release --product ResolutionBar
  binary_directory="$(swift build "${swift_options[@]}" --triple "$target" -c release --show-bin-path)"
  cp "$binary_directory/ResolutionBar" "$build_root/slices/ResolutionBar-$architecture"
done

app="$output/ResolutionBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun lipo -create "$build_root/slices/ResolutionBar-arm64" "$build_root/slices/ResolutionBar-x86_64" \
  -output "$app/Contents/MacOS/ResolutionBar"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ResolutionBar</string>
  <key>CFBundleIdentifier</key><string>local.resolutionbar.app</string>
  <key>CFBundleName</key><string>ResolutionBar</string>
  <key>CFBundleDisplayName</key><string>ResolutionBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 ResolutionBar contributors. MIT License.</string>
</dict></plist>
PLIST
chmod +x "$app/Contents/MacOS/ResolutionBar"
plutil -lint "$app/Contents/Info.plist"
xcrun lipo "$app/Contents/MacOS/ResolutionBar" -verify_arch arm64 x86_64
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"
ditto -c -k --keepParent "$app" "$output/ResolutionBar.zip"
(cd "$output" && shasum -a 256 ResolutionBar.zip > ResolutionBar.zip.sha256)
printf 'Built universal app: %s\nArchive: %s\n' "$app" "$output/ResolutionBar.zip"
