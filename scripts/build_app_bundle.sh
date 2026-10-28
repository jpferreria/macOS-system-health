#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

CONFIG="${1:-release}"
INSTALL_TO_APPS="${2:-false}"

echo "Building CritMonitor executable ($CONFIG)..."
swift build -c "$CONFIG"

STAGE_DIR="/tmp/CritMonitor-stage"
APP_DIR="$STAGE_DIR/CritMonitor.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$STAGE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp -X "$PROJECT_DIR/.build/$CONFIG/CritMonitor" "$MACOS_DIR/CritMonitor"

# Generate AppIcon.icns in /tmp to avoid iCloud Drive FinderInfo attributes
ICONSET_DIR="$STAGE_DIR/AppIcon.iconset"
ICNS_PATH="$STAGE_DIR/AppIcon.icns"
mkdir -p "$ICONSET_DIR"
swift - "$ICONSET_DIR" << 'SWIFT_ICON'
import AppKit

let iconsetPath = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, filename) in sizes {
    let size = NSSize(width: px, height: px)
    let img = NSImage(size: size)
    img.lockFocus()

    let rect = NSRect(origin: .zero, size: size).insetBy(dx: CGFloat(px) * 0.06, dy: CGFloat(px) * 0.06)
    let path = NSBezierPath(roundedRect: rect, xRadius: CGFloat(px) * 0.22, yRadius: CGFloat(px) * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.24, alpha: 1.0),
        NSColor(calibratedRed: 0.16, green: 0.26, blue: 0.52, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -45)

    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.48, weight: .bold)
    if let symbol = NSImage(systemSymbolName: "waveform.path.ecg.rectangle.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symSize = symbol.size
        let symRect = NSRect(
            x: (CGFloat(px) - symSize.width) / 2.0,
            y: (CGFloat(px) - symSize.height) / 2.0,
            width: symSize.width,
            height: symSize.height
        )
        NSColor.white.set()
        symbol.draw(in: symRect)
    }

    img.unlockFocus()
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(filename)"))
    }
}
SWIFT_ICON
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH" || true

if [[ -f "$ICNS_PATH" ]]; then
    cp -X "$ICNS_PATH" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CritMonitor</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.critmonitor.macos.app</string>
    <key>CFBundleName</key>
    <string>CritMonitor</string>
    <key>CFBundleDisplayName</key>
    <string>CritMonitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

rm -rf "$PROJECT_DIR/CritMonitor.app"
cp -R "$APP_DIR" "$PROJECT_DIR/CritMonitor.app"
echo "Successfully built $PROJECT_DIR/CritMonitor.app"

if [[ "$INSTALL_TO_APPS" == "--install" ]]; then
    pkill -x CritMonitor || true
    rm -rf "/Applications/CritMonitor.app"
    cp -R "$APP_DIR" "/Applications/CritMonitor.app"
    echo "Installed to /Applications/CritMonitor.app"
fi
