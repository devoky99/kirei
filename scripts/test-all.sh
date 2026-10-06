#!/usr/bin/env bash
# Baut und testet Kirei auf iOS (Simulator) und macOS.
# Regel: eine Aufgabe ist erst fertig, wenn dieses Skript grün ist.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n▸ %s\n' "$1"; }

step "Kern-Tests auf dem Mac"
swift test --package-path Packages/KireiKit

step "Kern-Tests im iOS-Simulator"
SIM_ID="$(xcrun simctl list devices available \
  | sed -nE 's/^ +iPhone[^(]* \(([0-9A-F-]{36})\).*/\1/p' \
  | head -n 1)"
if [[ -z "$SIM_ID" ]]; then
  echo "Kein iPhone-Simulator gefunden. In Xcode unter Settings > Components einen installieren."
  exit 1
fi
(cd Packages/KireiKit && xcodebuild test -scheme KireiKit-Package -destination "id=$SIM_ID" -quiet)

step "App für iPhone und iPad bauen (Simulator)"
xcodebuild build -project Kirei.xcodeproj -scheme Kirei \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO -quiet

step "App für den Mac bauen"
xcodebuild build -project Kirei.xcodeproj -scheme Kirei \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -quiet

step "Prüfstand bauen"
swift build --package-path Packages/Pruefstand

printf '\n✓ Alles grün auf iOS und macOS.\n'
