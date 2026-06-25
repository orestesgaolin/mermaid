#!/usr/bin/env bash
# ELK parity oracle. Renders a mermaid source through BOTH the real mermaid.js
# (via mermaid-cli + headless Chrome — the trusted "official" ground truth) and
# our pure-Dart pipeline, then writes a side-by-side PNG and both SVGs for
# direct comparison.
#
# Usage:  tool/elk_oracle.sh <diagram.mmd> <out-dir>
#
# Requires: npx @mermaid-js/mermaid-cli (mmdc) with a cached Chrome, rsvg-convert
# and magick (ImageMagick) on PATH.
set -euo pipefail
SRC="${1:?usage: elk_oracle.sh <diagram.mmd> <out-dir>}"
OUT="${2:?usage: elk_oracle.sh <diagram.mmd> <out-dir>}"
mkdir -p "$OUT"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Official: real mermaid.js.
npx --no-install @mermaid-js/mermaid-cli -i "$SRC" -o "$OUT/official.svg" -b white >/dev/null 2>&1

# Ours: pure-Dart render.
( cd "$HERE/.." && dart run tool/render_svg.dart "$SRC" ) > "$OUT/ours.svg"

rsvg-convert -b white "$OUT/official.svg" -o "$OUT/official.png"
rsvg-convert -b white "$OUT/ours.svg"     -o "$OUT/ours.png"

magick "$OUT/official.png" -resize x1400 "$OUT/_o.png"
magick "$OUT/ours.png"     -resize x1400 "$OUT/_u.png"
magick "$OUT/_o.png" -bordercolor "#0a0" -border 3 -gravity North -background white \
  -splice 0x24 -annotate +0+2 "OFFICIAL mermaid.js" "$OUT/_l.png"
magick "$OUT/_u.png" -bordercolor "#a00" -border 3 -gravity North -background white \
  -splice 0x24 -annotate +0+2 "OURS" "$OUT/_r.png"
magick "$OUT/_l.png" "$OUT/_r.png" +append "$OUT/compare.png"
rm -f "$OUT/_o.png" "$OUT/_u.png" "$OUT/_l.png" "$OUT/_r.png"
echo "wrote $OUT/compare.png (+ official.svg, ours.svg)"
