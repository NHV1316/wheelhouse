#!/bin/bash
# Builds Wheelhouse.app into ./build. Needs Xcode or the Command Line Tools
# (run `xcode-select --install` once if swiftc is missing).
set -e
cd "$(dirname "$0")"
if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Run: xcode-select --install   then run this script again."
  exit 1
fi
APP=build/Wheelhouse.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
echo "Compiling (Apple silicon + Intel)..."
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" Sources/main.swift -o "build/Wheelhouse-$ARCH"
done
lipo -create build/Wheelhouse-arm64 build/Wheelhouse-x86_64 -output "$APP/Contents/MacOS/Wheelhouse"
rm build/Wheelhouse-arm64 build/Wheelhouse-x86_64
cp Info.plist "$APP/Contents/Info.plist"
iconutil -c icns Icon/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
echo "Drag it into Applications, then open it."
