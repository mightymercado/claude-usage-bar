#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building Claude Usage Bar..."
swift build -c release 2>&1

APP_DIR="build/ClaudeUsageBar.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp .build/release/ClaudeUsageBar "$APP_DIR/Contents/MacOS/ClaudeUsageBar"

# Copy resource bundle if it exists
BUNDLE=$(find .build/release -name "ClaudeUsageBar_ClaudeUsageBar.bundle" -maxdepth 1 2>/dev/null | head -1)
if [ -n "$BUNDLE" ]; then
    cp -R "$BUNDLE" "$APP_DIR/Contents/Resources/"
fi

echo ""
echo "Build complete: $APP_DIR"
echo ""
echo "To run:  open $APP_DIR"
echo "To install: cp -R $APP_DIR /Applications/"
