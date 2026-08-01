#!/bin/sh
# Compiles and runs the video-export smoke test against the app's own
# non-UI sources. Usage: smoke-video.sh <image> <out.mp4>
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
MACOS="$(dirname "$HERE")"

"$HERE/build-bridge.sh"

# Top-level code must live in main.swift when compiling multiple files.
STAGE="${TMPDIR:-/tmp}/primitive-video-smoke-src"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$HERE/smoke-video.swift" "$STAGE/main.swift"

BIN="${TMPDIR:-/tmp}/primitive-video-smoke"
xcrun swiftc -O -o "$BIN" \
    "$STAGE/main.swift" \
    "$MACOS/PrimitiveDos/Bridge/EngineModels.swift" \
    "$MACOS/PrimitiveDos/Bridge/EngineClient.swift" \
    "$MACOS/PrimitiveDos/Preview/ShapeDrawing.swift" \
    "$MACOS/PrimitiveDos/Export/VideoExporter.swift" \
    -import-objc-header "$MACOS/Vendor/libprimitive.h" \
    -L"$MACOS/Vendor" -lprimitive \
    -framework CoreFoundation -framework Security \
    -framework AVFoundation -framework CoreVideo -framework VideoToolbox

"$BIN" "${1:?image path required}" "${2:?output path required}"
