# Parity issues — round 2 (user side-by-side vs mermaid.js)

Found by live comparison against the mermaid.js CDN (which the earlier render-only
verification couldn't do). Status: ⬜ open · 🔬 validated · 🛠 fixed · ✅ verified.

| ID | Diagram | Symptom | Class | Status | Resolution |
|---|---|---|---|---|---|
| P1 | ishikawa | wrong branch angles, no arrowheads, fish on wrong side | render | ✅ | already-fixed (stale deploy); current code matches upstream (head wedge on right, 82° bones, arrowheads) — verified by render |
| P2 | architecture | vastly different colors, icons, shapes | render | 🛠 | FIXED: new `mermaid-architecture` 80×80 icon pack (#087ebf box + white line-art) + style-aware `renderIcon` (per-element fill/stroke) |
| P3 | eventModeling | multi-word names → JS parse error; ours too lenient | sample | 🛠 | FIXED: website sample → single-token names (`OrderPage`…); renders correctly |
| P4 | railroad | JS: "no diagram type detected for railroad-diagram" | not-a-bug | ✅ | our header `railroad-diagram` matches upstream exactly; the released CDN predates railroad so it can't render it — nothing to fix |
| P5 | xychart | y-axis title should be rotated; ours horizontal | render | ✅ | already-fixed (stale deploy); SVG shows `rotate(270 …)` on the y-title — verified |
| P6 | timeline | vertical lines stop at icon, not boundary | render | 🛠 | FIXED: divider was only drawn for periods with events; now drawn for every period to the full-height boundary |
| P7 | journey | drop-lines stop at icon, not boundary | render | ✅ | already-fixed (stale deploy); drop-line goes taskY→maxHeight(450) past the faces — verified |
| P8 | sankey | JS fills full width; ours ~50% narrower | render | 🛠 | FIXED: default canvas was 600×400; upstream is 600×600 (`height ?? width`). Matched aspect → contain-fit embed now renders at the same width |
| P9 | packet | no inter-field gap; bit labels misaligned | render | 🛠 | FIXED: bit-number baseline corrected to wordY-2 (gap was already correct) |
| P10 | mindmap | `layout: elk` relayouts in JS; ours ignores engine | layout-engine | ✅ | FIXED: `layoutMindmap` now threads the resolved engine; `elk`/`tidy-tree` relayout the mindmap as a left-to-right tidy tree (shared `tidyTreeLayout`) with smooth horizontal edges, mirroring upstream's hierarchical relayout under a `layout:` directive. Radial stays the default. Verified by render + regression test. |
| P11 | treemap | JS draws a border around each group | render | ✅ | already-present (stale deploy); section rects have cScalePeer stroke width 2 @ opacity 0.4 (upstream's exact faint border) — verified in SVG |
| P12 | venn | invalid sample → JS lexical error; ours blank | sample | 🛠 | FIXED: website sample → valid `set X` / `union A,B["L"]`; renders the overlap + union label |
| P13 | wardley | dotted lines, red arrowhead, rotated y-label, missing Evolution label | render | ✅ | already-fixed (stale deploy); SVG shows `dasharray 5,5`, `#dc3545` arrowhead, `rotate(-90)` y-label, "Evolution" label — verified |
| P14 | hand-drawn (elk/tidy) | edges not hand-drawn under alt engines | cross-cutting | ✅ | not-reproduced; edges ARE roughened under elk & tidy-tree (verified render) — stale deploy |
| P15 | arrows (tidy/elk) | two edges between same nodes collapse to one line w/ two arrowheads | cross-cutting | 🛠 | FIXED: tidy-tree straight routing now fans out parallel/antiparallel edges by a perpendicular bend → two distinct curves |

## Root cause for ~half the tickets: STALE DEPLOYED WEBSITE

P1, P5, P7, P11, P13 (and P14) were **already fixed** in commit `df63e10` / the theme-wire pass, but the deployed GitHub Pages site predates those commits — so the user's side-by-side compared current mermaid.js against our *old* build. Verified by rendering current code (CLI → SVG): each matches upstream. **The website needs rebuilding/redeploying.** The genuinely-new code fixes this round are P2, P6, P8, P9, P15 (+ sample fixes P3, P12).

## Validated root causes / fix plan

- **P3** — `apps/website/lib/samples.dart` eventmodeling sample uses `tf 01 ui Order Page` (multi-word name). Upstream grammar requires single-token names (`tf 01 ui CartUI`). Fix sample → single-token names; (parity) tighten parser to reject embedded spaces in a name.
- **P4** — Our `detect.dart` header `railroad-diagram` equals upstream `railroadDetector.ts` `/^\s*railroad-diagram/i`. The released mermaid@11 CDN predates railroad, so it can't render it; nothing to fix on our side. Action: document; (optional) add `railroad-ebnf`/`-abnf`/`-peg` aliases that upstream also registers.
- **P12** — venn sample must be `set Frontend` / `union Frontend,Backend["Label"]` / optional `:N`; bracket is a single display label, not a list, and there is no `intersect`/`as`. Fix sample; verify our venn parser+layout render the correct syntax.
- **P1,P2,P5,P6,P7,P8,P9,P11,P13** — single-diagram render fixes; validate each against the upstream renderer and fix in that diagram's file.
- **P10** — mindmap upstream uses cose-bilkent and re-lays-out under a layout directive; our mindmap is radial-only and ignores the engine. Decide: wire a layered fallback under `layout: elk`, or document as an intentional deviation.
- **P14,P15** — both touch flowchart edge handling under the tidy-tree/elk engines (`layout_engines.dart` / `flow_layout.dart`) + the rough post-process; handle together to avoid conflicts.

## Note on verification
Earlier "full parity" was structural render-diff + upstream constants, NOT a live
pixel-diff — which is why these slipped through. This round is driven by the user's
actual mermaid.js comparison.
