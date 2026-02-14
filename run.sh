#!/bin/sh

set -xeu

APP_NAME="NEXGallery"
BUNDLE_DIR="$APP_NAME.app"

# Build
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
swiftc *.swift -o "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
cp Info.plist "$BUNDLE_DIR/Contents/Info.plist"

# Lanuch
open "$BUNDLE_DIR"
