#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_DIR="build/ANTICATERKnobControl.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

xcrun swiftc \
  -parse-as-library \
  Sources/KnobControlGUI/main.swift \
  -o "$APP_DIR/Contents/MacOS/ANTICATERKnobControl"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>ANTICATERKnobControl</string>
  <key>CFBundleIdentifier</key>
  <string>cc.codex.anticater-knob-control</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>手轮控制台</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${ANTICATER_CODE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
      | head -n 1
  )"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "signing with: $SIGN_IDENTITY" >&2
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
else
  echo "signing with: ad-hoc" >&2
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
