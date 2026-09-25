#!/bin/zsh
# Build SwitchUp.app (universal, macOS 14+).
#   ./build.sh            dev build: sign with Apple Development, install to ~/Applications
#   RELEASE=1 ./build.sh  just build into build/ (release.sh signs + notarizes it)
set -e
cd "$(dirname "$0")"

APP=${BUILD_DIR:-build-dev}/SwitchUp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp assets/AppIcon.icns "$APP/Contents/Resources/"

for arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -target $arch-apple-macos14.0 *.swift -o ${BUILD_DIR:-build-dev}/SwitchUp-$arch
done
lipo -create ${BUILD_DIR:-build-dev}/SwitchUp-arm64 ${BUILD_DIR:-build-dev}/SwitchUp-x86_64 -output "$APP/Contents/MacOS/SwitchUp"
rm ${BUILD_DIR:-build-dev}/SwitchUp-arm64 ${BUILD_DIR:-build-dev}/SwitchUp-x86_64

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SwitchUp</string>
  <key>CFBundleIdentifier</key><string>com.shailenparmar.switchup</string>
  <key>CFBundleExecutable</key><string>SwitchUp</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>Shailen Parmar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>GCSupportsControllerUserInteraction</key><true/>
  <key>GCSupportedGameControllers</key>
  <array>
    <dict><key>ProfileName</key><string>ExtendedGamepad</string></dict>
  </array>
</dict>
</plist>
PLIST

[ -n "$RELEASE" ] && { echo "Built $APP"; exit 0; }

# Stable identity so the Accessibility grant survives rebuilds (ad-hoc "-" as fallback).
ID=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | awk '{print $2}')
codesign --force --sign "${ID:--}" "$APP"

mkdir -p ~/Applications
pkill -x SwitchUp 2>/dev/null || true
rm -rf ~/Applications/SwitchUp.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/SwitchUp.app"
