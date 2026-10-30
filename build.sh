#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
OUTPUT="${1:-dist}"
mkdir -p "$OUTPUT/TypeBridge.app/Contents/MacOS" "$OUTPUT/TypeBridge.app/Contents/Resources" .build-cache
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -module-cache-path .build-cache \
  Sources/Detector.swift Sources/System.swift Sources/App.swift Sources/main.swift \
  -framework AppKit -framework Carbon -framework ApplicationServices -framework ServiceManagement \
  -o "$OUTPUT/TypeBridge.app/Contents/MacOS/TypeBridge"
cp Resources/Info.plist "$OUTPUT/TypeBridge.app/Contents/Info.plist"
codesign --force --sign - --identifier local.bogdan.TypeBridge "$OUTPUT/TypeBridge.app"
codesign --verify --deep --strict "$OUTPUT/TypeBridge.app"
echo "Built: $OUTPUT/TypeBridge.app"
