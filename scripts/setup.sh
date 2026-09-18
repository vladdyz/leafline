#!/usr/bin/env bash
#
# Phase 0 setup. Run this ONCE, from the directory ABOVE this repo folder.
#
#   ./receipt-tracker/scripts/setup.sh com.yourdomain
#
# It creates the Flutter scaffold, adds dependencies at their current
# versions, and overlays the files from this skeleton on top.
#
# Why a script instead of a checked-in pubspec with pinned versions:
# pinned versions go stale. `flutter pub add` resolves whatever is current
# the day you run it, which is what you want on day one of a project.

set -euo pipefail

ORG="${1:-}"
if [ -z "$ORG" ]; then
  echo "usage: $0 <org>    e.g. $0 com.yourdomain" >&2
  exit 1
fi

SKELETON="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="receipt_tracker"
WORKDIR="$(dirname "$SKELETON")"

cd "$WORKDIR"

if [ -d "$APP_NAME" ]; then
  echo "error: $WORKDIR/$APP_NAME already exists. Move it aside first." >&2
  exit 1
fi

echo "==> Checking toolchain"
command -v flutter >/dev/null || { echo "flutter not on PATH" >&2; exit 1; }
flutter --version

echo "==> Creating Flutter project (Android only)"
flutter create \
  --org "$ORG" \
  --project-name "$APP_NAME" \
  --platforms android \
  --template app \
  "$APP_NAME"

cd "$APP_NAME"

echo "==> Adding runtime dependencies"
flutter pub add \
  flutter_riverpod \
  sqflite \
  path \
  path_provider \
  image_picker \
  uuid \
  intl

echo "==> Adding dev dependencies"
flutter pub add --dev \
  mocktail \
  flutter_lints

echo "==> Adding integration_test from the SDK"
flutter pub add --dev --sdk=flutter integration_test

echo "==> Overlaying skeleton files"
# Everything except the android overlay, which needs the package path resolved.
for item in analysis_options.yaml README.md .gitignore .github docs lib test scripts; do
  if [ -e "$SKELETON/$item" ]; then
    cp -R "$SKELETON/$item" .
  fi
done

echo "==> Placing the Kotlin OCR stub"
PKG_PATH="$(echo "$ORG.$APP_NAME" | tr '.' '/')"
KOTLIN_DIR="android/app/src/main/kotlin/$PKG_PATH"
mkdir -p "$KOTLIN_DIR/ocr"
sed "s|^package .*|package $ORG.$APP_NAME.ocr|" \
  "$SKELETON/android_overlay/ocr/OcrPlugin.kt" > "$KOTLIN_DIR/ocr/OcrPlugin.kt"
echo "    wrote $KOTLIN_DIR/ocr/OcrPlugin.kt"
echo "    NOTE: wire it up in MainActivity.kt — see docs/decisions and the design doc."

echo "==> Verifying"
flutter analyze
dart format --set-exit-if-changed .
flutter test

cat <<'EOF'

Phase 0 complete.

Next:
  1. git init && git add -A && git commit -m "Phase 0: skeleton, utils, CI"
  2. Push to GitHub and confirm the Actions run goes green.
  3. Register OcrPlugin in MainActivity.configureFlutterEngine and confirm
     the stub returns its hardcoded blocks. Only then start Phase 1.

EOF
