#!/bin/sh
# Builds the Go engine as a static C archive for the Mac app, and refreshes
# the app icon asset from the repo's generated icon. Runs as an Xcode
# pre-build phase; incremental via Go's build cache (~0.3s when unchanged).
#
# Xcode script phases run with a bare PATH, and Go lives at /usr/local/go on
# this machine — resolve it rather than assuming Homebrew.
set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GO="$(command -v go 2>/dev/null || echo /usr/local/go/bin/go)"

cd "$REPO"
CGO_ENABLED=1 GOARCH=arm64 "$GO" build -buildmode=c-archive \
    -o macos/Vendor/libprimitive.a ./bridge

ICON_SRC="$REPO/build/appicon.png"
ICON_DST="$REPO/macos/PrimitiveDos/Assets.xcassets/AppIcon.appiconset/appicon.png"
if [ -f "$ICON_SRC" ] && [ -d "$(dirname "$ICON_DST")" ]; then
    cp "$ICON_SRC" "$ICON_DST"
fi
