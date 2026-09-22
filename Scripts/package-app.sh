#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/JevPaste.app"

cd "$PROJECT_DIR"
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BIN_DIR/JevPaste" "$APP_DIR/Contents/MacOS/JevPaste"
chmod 755 "$APP_DIR/Contents/MacOS/JevPaste"
codesign --force --deep --sign - --options runtime "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Created $APP_DIR"
