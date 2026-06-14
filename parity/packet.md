# packet — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Config defaults (`config.schema.yaml` PacketDiagramConfig): `rowHeight=32`, `bitWidth=32`, `bitsPerRow=32`, `paddingX=5`, `paddingY=5`, `showBits=true`.
- `db.ts:getConfig` — when `showBits` is true, `paddingY += 10` (so effective vertical row padding becomes 15).
- `renderer.ts:draw` — `totalRowHeight = rowHeight + paddingY`; `svgHeight = totalRowHeight*(words.length+1) - (title ? 0 : rowHeight)`; `svgWidth = bitWidth*bitsPerRow + 2`. Note the layout always reserves one extra `totalRowHeight` band at the bottom; the title (if any) is drawn there.
- `renderer.ts:drawWord` — `wordY = rowNumber*(rowHeight+paddingY) + paddingY`. Per block: `blockX = (start % bitsPerRow)*bitWidth + 1`; `width = (end-start+1)*bitWidth - paddingX` (the `-paddingX` leaves a horizontal gap between adjacent blocks); rect height = `rowHeight`, class `packetBlock`.
- Block label: centered (`text-anchor=middle`, `dominant-baseline=middle`) at block center, class `packetLabel`.
- Bit numbers (`showBits`): drawn at `wordY - 2` (above the row), class `packetByte start`/`packetByte end`. Single-bit block → one number centered (`text-anchor=middle`); multi-bit → start number left-anchored at `blockX`, end number right-anchored at `blockX+width`.
- Title: `renderer.ts:draw` appends it at the BOTTOM, `x=svgWidth/2`, `y=svgHeight - totalRowHeight/2`, centered both axes, class `packetTitle`.
- `parser.ts:populate` / `getNextFittingBlock` — splits blocks that cross a `bitsPerRow` boundary into row segments; grouped into `PacketWord[]` (one array per row). Contiguity enforced; zero-bit and end<start rejected.
- `styles.ts` — colors are HARDCODED, theme-independent: block fill `#efefef`, stroke `black` width `1`, label `black` 12px, byte numbers `black` 10px, title `black` 14px. (Overridable only via `packet` style options.)

## How mermaid_dart implements it
- `packet.dart:parsePacket` — line/regex parser. Header `^packet(-beta)?`; field regex `^(\+?\d+)(?:\s*-\s*(\d+))?\s*:\s*"(.*)"$`. Supports `start`, `start-end`, and `+count` continuation. Enforces contiguity (same message as upstream). Title from frontmatter or in-body `title`.
- `packet.dart:layoutPacket` — constants: `bitsPerRow=32`, `bitWidth=30.0`, `rowHeight=34.0`, `rowGap=8.0`, `bitLabelH=14.0`.
- `rowTop(row) = bitLabelH + row*(rowHeight + rowGap + bitLabelH)`; splits each field at row boundaries; `x = (bit%bitsPerRow)*bitWidth`, `w = (segEnd-bit+1)*bitWidth` (NO horizontal gap), rect height `rowHeight`.
- Block: `SceneShape(RectGeometry)` fill `theme.mainBkg`, stroke `theme.nodeBorder` width 1; label `SceneText` centered, color `theme.textColor`, fontSize `theme.fontSize - 3`.
- Bit numbers: start at top-left (`bounds x..., y-bitLabelH`, left-aligned, fontSize 10); end at top-right only if segment >1 bit. Always shown (no `showBits` toggle).
- Title: drawn at TOP of the grid (`bounds.top - pad - size.height`), fontWeight 700, fontSize `theme.fontSize`, color `theme.titleColor`, left-origin bounds (not centered).
- Wraps each segment in `SceneGroup` with `semanticLabel`. Pads scene by `pad=12`.

## Discrepancies
1. `[open] (high) Title position: bottom (upstream) vs top (ours)`
   - Upstream always draws the title in a reserved band BELOW the grid, horizontally centered. Ours draws it ABOVE the grid, left-origin bounds (effectively left-ish, not centered). Structural placement difference.
2. `[open] (medium) Block fill/stroke use theme colors instead of hardcoded packet palette`
   - Upstream packet is theme-independent: fill `#efefef`, stroke/text `black`. Ours uses `theme.mainBkg` (e.g. `#ececff`) fill and `theme.nodeBorder` (e.g. purple) stroke + `theme.textColor` label. Default light theme will look lilac/purple instead of grey/black.
3. `[open] (medium) No horizontal gap between blocks (paddingX)`
   - Upstream subtracts `paddingX` (5) from each block width, leaving a visible gap between adjacent blocks. Ours uses full `bitWidth*bits`, so blocks abut with no gap.
4. `[open] (medium) Bit/row geometry constants differ`
   - bitWidth 30 vs 32; rowHeight 34 vs 32; vertical spacing model `rowGap 8 + bitLabelH 14 = 22` between rows vs upstream effective `paddingY 15` (with showBits). Overall scale and proportions differ.
5. `[open] (low) Font sizes for label/title differ`
   - Upstream label fixed 12px, title 14px. Ours label `fontSize-3` (=13 at default 16) and title `fontSize` (=16). Slightly larger than upstream.
6. `[open] (low) No showBits toggle`
   - Upstream `showBits` config can hide bit numbers (and removes the +10 paddingY). Ours always renders bit numbers; no config plumbed.
7. `[open] (low) Bit number vertical placement model differs`
   - Upstream places numbers just above the row at `wordY-2` within the same paddingY band. Ours reserves a dedicated `bitLabelH=14` strip above every row, changing row rhythm.
8. `[open] (low) Single-bit start number not centered`
   - Upstream centers the start bit number over single-bit blocks (`text-anchor=middle`). Ours always left-aligns the start number even for a 1-bit block.

## Proposed fixes
1. In `packet.dart:layoutPacket`, move the title block to AFTER the grid (below `bounds.bottom`) and center it horizontally over `bounds.width` (center-aligned SceneText).
2. In `packet.dart:layoutPacket`, replace `Fill(theme.mainBkg)`/`Stroke(theme.nodeBorder)`/label `theme.textColor` with packet-specific constants (fill `0xffefefef`, stroke/text black) or a dedicated theme packet palette.
3. In `packet.dart:layoutPacket`, introduce `paddingX=5` and set `w = (segEnd-bit+1)*bitWidth - paddingX` (and offset `x` by +1 like upstream's `blockX+1`).
4. In `packet.dart:layoutPacket`, change constants to `bitWidth=32`, `rowHeight=32`, and align vertical spacing to upstream's `paddingY` (15 with bits) model in `rowTop`.
5. In `packet.dart:layoutPacket`, set `labelStyle` fontSize to 12 and title fontSize to 14 (independent of theme.fontSize).
6. In `packet.dart` add a `showBits` flag (default true) to `Packet`/`layoutPacket`; skip bit-number SceneText and drop the bit strip when false.
7. In `packet.dart:layoutPacket`, place bit numbers at `y = rowTop(row) - 2` within a paddingY band rather than a separate `bitLabelH` strip (depends on fix 4).
8. In `packet.dart:layoutPacket`, when `segEnd == bit` (single bit), emit one centered bit number instead of a left-aligned one.

## Implementation log
All fixes applied in `packet.dart:layoutPacket` (+ `Packet` gained a `showBits` flag, default true; added `import '../../color.dart'`).

1. (high) Title position — Done. Title now drawn in a reserved band BELOW the grid (`y = bounds.bottom`, band height = `rowHeight + paddingY`), centered horizontally over `bounds.width` (default `TextAlignH.center`), black 14px.
2. (medium) Block fill/stroke palette — Done. Replaced theme colors with hardcoded upstream constants: fill `Color(0xffefefef)`, stroke/label/byte text `Color(0xff000000)`. Theme-independent like upstream styles.ts.
3. (medium) Horizontal gap (paddingX) — Done. `x = colStart*bitWidth + 1`; `w = bits*bitWidth - paddingX` with `paddingX = 5`.
4. (medium) Bit/row geometry constants — Done. `bitWidth = 32`, `rowHeight = 32`; vertical model switched to upstream `rowTop(row) = row*(rowHeight+paddingY) + paddingY` with `paddingY = 15` when showBits (5 base + 10), `5` otherwise.
5. (low) Font sizes — Done. Label fixed 12px, title 14px, byte numbers 10px; independent of `theme.fontSize`.
6. (low) showBits toggle — Done (model-level). `Packet.showBits` (default true) drops bit numbers and the +10 paddingY when false. Config-file plumbing to read `packet.showBits` from frontmatter/config is not wired (no config surface in our parser today); default true matches mermaid default. Noted as a minor follow-up, not a parity gap for default rendering.
7. (low) Bit number vertical placement — Done. Bit numbers placed in a band whose baseline lands at `wordY - 2` (band top = `y - 2 - bitLabelH`), within the paddingY rhythm rather than a dedicated strip per row.
8. (low) Single-bit start number centered — Done. When `segEnd == bit`, emit one center-anchored start number spanning the block width; multi-bit keeps left start + right end.

Note: `measurer` parameter retained in `layoutPacket` signature (public API) though no longer used internally — title sizing now uses a fixed band like upstream.

### P9 follow-up (bit-number baseline alignment)
Verified against renderer.ts: horizontal `paddingX` gap was already correct
(`x = colStart*bitWidth + 1`, `w = bits*bitWidth - paddingX`, paddingX=5),
matching upstream `drawWord`. Remaining defect was the bit-number *vertical*
alignment: upstream draws bit numbers with `dominant-baseline:auto` at
`y = wordY - 2`, so the text baseline (not its center) lands at `wordY-2`.
Our SVG backend puts a single line's baseline at `bounds.top + bounds.height*0.78`,
so the band top is now `y - 2 - bitLabelH*0.78` (was `y - 2 - bitLabelH`),
landing the baseline exactly at `wordY-2` instead of ~3px too high.
