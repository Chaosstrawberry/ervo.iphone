#!/bin/bash
# Kopiert das iPhone-Projekt in deinen Ordner "Dokumente" und öffnet es in Xcode.
DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/Documents/Ervo-Browser iPhone-App"
if [ ! -d "/Applications/Xcode.app" ]; then
  osascript -e 'display dialog "Xcode ist noch nicht installiert. Bitte zuerst Xcode aus dem Mac App Store laden und einmal öffnen." buttons {"App Store öffnen"} default button 1'
  open "macappstore://apps.apple.com/app/xcode/id497799835"
  exit 0
fi
mkdir -p "$TARGET"
cp -R "$DIR/Ervo-Browser iPhone-App/." "$TARGET/"
open "$TARGET/ErvoBrowser.xcodeproj"
