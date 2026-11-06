#!/bin/sh
# Builds the hands-free spike as an .app (macOS needs a Bluetooth usage description on the launching app) and runs it.
# Usage: spikes/hfp/run.sh "S24 FE"   then type commands: dial <number> | answer | end | audio | phone | quit
set -e
cd "$(dirname "$0")"
OUT="${TMPDIR:-/tmp}/myna-hfp"; APP="$OUT/Myna HFP.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/hfp"
cp Info.plist "$APP/Contents/Info.plist"
codesign -s - -f "$APP" >/dev/null 2>&1
open -W --stdin /dev/stdin --stdout /dev/stdout --stderr /dev/stderr "$APP" --args "${1:-S24}"
