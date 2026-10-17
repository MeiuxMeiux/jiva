#!/usr/bin/env bash
# raster — render the hand-written SVGs to the PNG/ICO files scrapers and home screens want.
# og.svg → og.png (1200×630, the self-hosted woff2 fonts, so the text matches the page);
# favicon.svg → apple-touch-icon.png (180), favicon.ico (16+32).
# Outputs are committed in site/src/ (stdlib build.py can't raster); rerun after editing either SVG.
# Needs: chrome-headless-shell (playwright cache, or $CHROME) + ImageMagick `convert` (ico only).
# Usage: raster.sh
set -euo pipefail
SRC=$(cd "$(dirname "$0")/../src" && pwd)
CHROME=${CHROME:-$(ls -d "$HOME"/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell 2>/dev/null | sort -V | tail -1)}
[ -x "$CHROME" ] || { echo "raster: no chrome-headless-shell (set CHROME=)"; exit 1; }
command -v convert >/dev/null || { echo "raster: ImageMagick convert missing"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

shot() { # shot <svg> <w> <h> <out.png>
  local svg=$1 w=$2 h=$3 out=$4
  {
    echo '<!DOCTYPE html><html><head><meta charset="utf-8"><style>'
    echo "@font-face{font-family:'Bricolage Grotesque';src:url('file://$SRC/fonts/bricolage-grotesque-latin-wght.woff2');font-weight:200 800}"
    echo "@font-face{font-family:'JetBrains Mono';src:url('file://$SRC/fonts/jetbrains-mono-latin-wght.woff2');font-weight:100 800}"
    echo "html,body{margin:0;background:#060128;overflow:hidden}svg{display:block;width:${w}px;height:${h}px}"
    echo '</style></head><body>'
    cat "$svg"
    echo '</body></html>'
  } > "$TMP/page.html"
  "$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --virtual-time-budget=2000 --window-size="$w,$h" --screenshot="$TMP/shot.png" \
    "file://$TMP/page.html" >/dev/null 2>&1
  convert "$TMP/shot.png" -crop "${w}x${h}+0+0" +repage -strip "$out"
  echo "raster: $(basename "$out") $(identify -format '%wx%h' "$out") $(stat -c %s "$out") B"
}

shot "$SRC/og.svg" 1200 630 "$SRC/og.png"
shot "$SRC/favicon.svg" 180 180 "$SRC/apple-touch-icon.png"
shot "$SRC/favicon.svg" 32 32 "$TMP/icon-32.png" >/dev/null
convert "$TMP/icon-32.png" \( "$TMP/icon-32.png" -resize 16x16 \) "$SRC/favicon.ico"
echo "raster: favicon.ico $(identify -format '%wx%h ' "$SRC/favicon.ico")"
