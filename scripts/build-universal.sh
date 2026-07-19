#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BUILD_DIR="$PROJECT_DIR/.build-universal"
APP_DIR="$PROJECT_DIR/dist/FTP Mount.app"

if ! xcode-select -p >/dev/null 2>&1; then
    print -u2 "Xcode is not configured. Install Xcode, open it once, then run:"
    print -u2 "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

rm -rf "$BUILD_DIR" "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swift build \
    --package-path "$PROJECT_DIR" \
    --configuration release \
    --arch arm64 \
    --scratch-path "$BUILD_DIR/arm64"

swift build \
    --package-path "$PROJECT_DIR" \
    --configuration release \
    --arch x86_64 \
    --scratch-path "$BUILD_DIR/x86_64"

ARM_BINARY="$BUILD_DIR/arm64/arm64-apple-macosx/release/FTPMount"
INTEL_BINARY="$BUILD_DIR/x86_64/x86_64-apple-macosx/release/FTPMount"

if [[ ! -x "$ARM_BINARY" || ! -x "$INTEL_BINARY" ]]; then
    print -u2 "One or both architecture builds did not produce the expected binary."
    exit 1
fi

xcrun lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$APP_DIR/Contents/MacOS/FTPMount"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/FTP Mount.icns" "$APP_DIR/Contents/Resources/FTP Mount.icns"
chmod 755 "$APP_DIR/Contents/MacOS/FTPMount"

# Ad-hoc signing is sufficient for local development. Distribution should use a
# Developer ID Application certificate followed by Apple notarization.
codesign --force --deep --sign - "$APP_DIR"

print "Built $APP_DIR"
xcrun lipo -info "$APP_DIR/Contents/MacOS/FTPMount"
