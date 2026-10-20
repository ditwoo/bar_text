#!/usr/bin/env bash
# Build bar_text and assemble a standalone macOS .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="bar_text"
BUNDLE="$ROOT/dist/$APP_NAME.app"

# Versioning: env overrides win, then the VERSION file, then a placeholder.
# CI sets VERSION and BUILD_NUMBER; a local build picks them up from VERSION.
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION 2>/dev/null || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

# Space-separated target architectures, e.g. ARCHS="arm64 x86_64" for a
# universal binary. Empty (the default) builds for the host arch only.
# Each arch is built separately and lipo'd together, so a universal build
# works with Command Line Tools alone (multi-`--arch` needs full Xcode).
ARCHS="${ARCHS:-$(uname -m)}"

bins=()
for arch in $ARCHS; do
    swift build -c release --arch "$arch"
    bins+=(".build/$arch-apple-macosx/release/$APP_NAME")
done

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

if [ "${#bins[@]}" -gt 1 ]; then
    lipo -create "${bins[@]}" -output "$BUNDLE/Contents/MacOS/$APP_NAME"
else
    cp "${bins[0]}" "$BUNDLE/Contents/MacOS/$APP_NAME"
fi
cp "packaging/Info.plist" "$BUNDLE/Contents/Info.plist"

# Stamp the resolved version into the bundle's Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$BUNDLE/Contents/Info.plist"

if [ -f "packaging/AppIcon.icns" ]; then
    cp "packaging/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "warning: packaging/AppIcon.icns missing (run scripts/make-icon.sh)"
fi

# Ad-hoc signature; keeps macOS happy when the app is moved around.
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || echo "warning: codesign failed (app still runnable)"

echo "Built $BUNDLE (version $VERSION, build $BUILD_NUMBER)"
