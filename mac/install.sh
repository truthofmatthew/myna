#!/bin/zsh
# Builds a Release copy and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
xcodebuild -project Myna.xcodeproj -scheme Myna -configuration Release \
  -derivedDataPath build -quiet build

pkill -x Myna || true
for _ in {1..50}; do pgrep -x Myna >/dev/null || break; sleep 0.1; done
rm -rf /Applications/Myna.app
ditto build/Build/Products/Release/Myna.app /Applications/Myna.app
open /Applications/Myna.app
echo "Installed. Myna is in the menu bar."
