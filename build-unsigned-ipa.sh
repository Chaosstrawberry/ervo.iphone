#!/bin/bash
# Run this script on macOS with Xcode installed, from the project folder.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/Ervo-Browser iPhone-App/ErvoBrowser.xcodeproj"
DERIVED="$ROOT/.build/DerivedData"
APP="$DERIVED/Build/Products/Release-iphoneos/ErvoBrowser.app"
OUT="$ROOT/dist/ErvoBrowser-unsigned.ipa"

xcodebuild \
  -project "$PROJECT" \
  -scheme ErvoBrowser \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

if [ ! -d "$APP" ]; then
  echo "Build output not found: $APP" >&2
  exit 1
fi

mkdir -p "$ROOT/dist" "$ROOT/.build/package/Payload"
rm -rf "$ROOT/.build/package/Payload/ErvoBrowser.app"
ditto "$APP" "$ROOT/.build/package/Payload/ErvoBrowser.app"
(cd "$ROOT/.build/package" && /usr/bin/zip -qry "$OUT" Payload)
echo "Created: $OUT"
