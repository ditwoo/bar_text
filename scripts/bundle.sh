#!/usr/bin/env bash
# Build bar_text and assemble a standalone macOS .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="bar_text"
BUNDLE="$ROOT/dist/$APP_NAME.app"

swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "packaging/Info.plist" "$BUNDLE/Contents/Info.plist"

if [ -f "packaging/AppIcon.icns" ]; then
    cp "packaging/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "warning: packaging/AppIcon.icns missing (run scripts/make-icon.sh)"
fi

# Ad-hoc signature; keeps macOS happy when the app is moved around.
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || echo "warning: codesign failed (app still runnable)"

echo "Built $BUNDLE"
