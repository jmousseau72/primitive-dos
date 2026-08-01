#!/bin/sh
# Builds the Go engine as a UNIVERSAL static C archive for the Mac app.
# Archive/Release builds link both arm64 and x86_64 — an arm64-only .a
# makes every Primitive* symbol come up undefined for the Intel slice.
# Runs as an Xcode pre-build phase; incremental via Go's build cache.
#
# Xcode script phases run with a bare PATH, and Go lives at /usr/local/go on
# this machine — resolve it rather than assuming Homebrew.
set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GO="$(command -v go 2>/dev/null || echo /usr/local/go/bin/go)"

cd "$REPO"
CGO_ENABLED=1 GOARCH=arm64 "$GO" build -buildmode=c-archive \
    -o macos/Vendor/libprimitive-arm64.a ./bridge
CGO_ENABLED=1 GOARCH=amd64 "$GO" build -buildmode=c-archive \
    -o macos/Vendor/libprimitive-amd64.a ./bridge
lipo -create -output macos/Vendor/libprimitive.a \
    macos/Vendor/libprimitive-arm64.a macos/Vendor/libprimitive-amd64.a
cp macos/Vendor/libprimitive-arm64.h macos/Vendor/libprimitive.h

# The app icon lives in Assets.xcassets/AppIcon.appiconset as a full macOS
# size matrix. After regenerating build/appicon.png (go run ./cmd/appicon),
# refresh the matrix from that folder with sips:
#   for the 10 sizes, e.g.: sips -z 1024 1024 ../../build/appicon.png --out icon_512x512@2x.png
