#!/bin/zsh
# Renders the Chrome Web Store images from src/*.html with Edge, as 24-bit PNGs (the store rejects alpha).
set -euo pipefail
cd "$(dirname "$0")"
edge="/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
shot() { "$edge" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --virtual-time-budget=4000 \
  --window-size=$2 --screenshot="$PWD/$3" "file://$PWD/src/$1.html" 2>/dev/null; }
for p in 1-meet 2-how 3-setup 4-camera 5-private; do shot $p 1280,800 screenshot-$p.png; done
shot tile-small 440,280 promo-small-440x280.png
shot tile-marquee 1400,560 promo-marquee-1400x560.png
python3 -c 'import sys; from PIL import Image
for f in sys.argv[1:]: Image.open(f).convert("RGB").save(f)' *.png
ls -1 *.png
