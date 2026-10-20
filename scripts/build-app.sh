#!/usr/bin/env bash
# Builds thumbs-out.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/thumbs-out.app"

# Apple Silicon only.
ARCHS=(--arch arm64)
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ThumbsOut" "$APP/Contents/MacOS/ThumbsOut"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run locally and to register as a login item.
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  # Quit politely so the app restores lid sleep itself; fall back to a signal if it doesn't.
  if pgrep -x ThumbsOut >/dev/null; then
    osascript -e 'quit app id "com.mj0lken.thumbs-out"' 2>/dev/null || true
    for _ in 1 2 3 4 5; do pgrep -x ThumbsOut >/dev/null || break; sleep 1; done
    pkill -x ThumbsOut 2>/dev/null || true
  fi
  rm -rf "/Applications/thumbs-out.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/thumbs-out.app"
  open /Applications/thumbs-out.app
fi
