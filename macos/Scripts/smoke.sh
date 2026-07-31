#!/bin/sh
# Compiles and runs the bridge smoke test. Usage: smoke.sh <image> <outdir>
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
MACOS="$(dirname "$HERE")"

"$HERE/build-bridge.sh"

BIN="${TMPDIR:-/tmp}/primitive-smoke"
xcrun swiftc -O -o "$BIN" "$HERE/smoke.swift" \
    -import-objc-header "$MACOS/Vendor/libprimitive.h" \
    -L"$MACOS/Vendor" -lprimitive \
    -framework CoreFoundation -framework Security

"$BIN" "${1:?image path required}" "${2:?output dir required}"
