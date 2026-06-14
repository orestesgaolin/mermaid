# Mermaid parity tracker

Per-diagram parity vs upstream mermaid.js. Pipeline: **analyze → implement → verify**. Each diagram has a detailed doc at `parity/<type>.md` (discrepancies, proposed fixes, implementation log).

**Parity:** 🟢 full · 🟡 minor-gaps (cosmetic / custom-theme / niche-config) · 🔴 major-gaps (structural)

**Stage:** ⬜ analyzed · 🛠 implemented · ✅ render-verified (output rendered via our SVG backend and checked for structural fidelity to mermaid.js)

**Status after implement pass:** 6 🟢 full · 22 🟡 minor · 0 🔴 major (was 0/8/20 after analysis). 333 fixes applied, 30 deferred. Gate: `dart analyze` clean · 412 tests · 184/184 corpus.

> Parity column is the implementing agent's code-level judgment (it read both codebases). **Stage ✅ = I rendered all 28 to PNG (SVG backend → rsvg-convert) and confirmed structural fidelity** (shapes, palette, layout) against mermaid.js. A live pixel-diff against the mermaid.js CDN was not run this session.

| Diagram | Engine(s) | Parity | Applied | Deferred | Stage | Doc | Note |
|---|---|:--:|:--:|:--:|:--:|---|---|
| **railroad** | — | 🟡 | 11 | 4 | ✅ | [railroad.md](railroad.md) | Applied 11 of 15 discrepancies (all high + remaining medium except the unreachable comment node). Rewrote rule layout… |
| **sequence** | — | 🟡 | 10 | 3 | ✅ | [sequence.md](sequence.md) | All visual fixes for the default theme applied and verified with `dart analyze` (sequence_layout.dart: No issues foun… |
| **mindmap** | — | 🟡 | 10 | 3 | ✅ | [mindmap.md](mindmap.md) | All 13 discrepancies addressed: 10 fixed, 3 deferred (1 intentional layout deviation, 1 blocked by no-theme-field rul… |
| **gitGraph** | — | 🟡 | 15 | 3 | ✅ | [gitGraph.md](gitGraph.md) | All 15 discrepancies addressed (12 fully, 3 partially with deferred remainders). Edits confined to git/git_graph.dart… |
| **c4** | — | 🟡 | 18 | 2 | ✅ | [c4.md](c4.md) | Rewrote layoutC4Diagram to use a row-packing grid (packShapes/layoutContainer) mirroring upstream Bounds.insert and d… |
| **sankey** | — | 🟡 | 12 | 2 | ✅ | [sankey.md](sankey.md) | Rewrote layoutSankey as a faithful d3-sankey port (BFS depths/heights, nodeAlignment, iterative relax+collision passe… |
| **kanban** | — | 🟡 | 11 | 2 | ✅ | [kanban.md](kanban.md) | Rewrote parser (rich KanbanTask cards with ticket/priority/assigned/icon, @{...} block parsing attached by node id wi… |
| **architecture** | — | 🟡 | 13 | 2 | ✅ | [architecture.md](architecture.md) | 13 of 15 discrepancies fully fixed; 2 deferred (layout solver and full icon packs) as they require subsystems/assets … |
| **classDiagram** | — | 🟡 | 9 | 1 | ✅ | [classDiagram.md](classDiagram.md) | 9 of 10 discrepancies fixed (all high/medium plus most low). The high-severity 10px font fix corrects box/member/titl… |
| **stateDiagram** | — | 🟡 | 13 | 1 | ✅ | [stateDiagram.md](stateDiagram.md) | All medium-severity and all but one low-severity discrepancy fixed. The composite cluster now draws an outer mainBkg … |
| **gantt** | — | 🟡 | 12 | 1 | ✅ | [gantt.md](gantt.md) | All 12 discrepancies applied (high+medium fully done; low items done or partially). Theme defaults inlined as exact h… |
| **requirement** | — | 🟡 | 11 | 1 | ✅ | [requirement.md](requirement.md) | All discrepancies 1-11 applied (high+medium+low); #12 deferred to skip-not-throw. dart analyze clean on the requireme… |
| **treemap** | — | 🟡 | 12 | 1 | ✅ | [treemap.md](treemap.md) | Rewrote treemap.dart to mirror upstream's d3 renderer: default-theme cScale/cScalePeer/cScaleLabel ordinal scales (ex… |
| **venn** | — | 🟡 | 15 | 1 | ✅ | [venn.md](venn.md) | Rewrote venn.dart for parity. Parser now handles set/union sizes (:N), bracket labels, free + indented text nodes, st… |
| **journey** | — | 🟡 | 17 | 0 | ✅ | [journey.md](journey.md) | All 17 discrepancies applied; dart analyze reports no errors. Two items are approximations rather than pixel-exact an… |
| **timeline** | — | 🟡 | 10 | 0 | ✅ | [timeline.md](timeline.md) | Rewrote layoutTimeline to upstream's vertical columnar topology and replaced the hardcoded palette with exact default… |
| **xychart** | — | 🟡 | 12 | 0 | ✅ | [xychart.md](xychart.md) | Rewrote layoutXyChart as a faithful port of upstream's Orchestrator + BaseAxis/LinearAxis/BandAxis + plot/title/data-… |
| **block** | — | 🟡 | 10 | 0 | ✅ | [block.md](block.md) | All 10 discrepancies implemented in block.dart (high→low). Extended BlockShape enum + _parseNode bracket map to mirro… |
| **cynefin** | — | 🟡 | 12 | 0 | ✅ | [cynefin.md](cynefin.md) | Full rewrite of cynefin.dart matching upstream renderer + boundaries. dart analyze clean. Two intentional minor devia… |
| **ishikawa** | — | 🟡 | 13 | 0 | ✅ | [ishikawa.md](ishikawa.md) | Full rewrite of ishikawa.dart to port the upstream vertical-spine fishbone layout: recursive IshikawaNode tree (level… |
| **wardley** | — | 🟡 | 11 | 0 | ✅ | [wardley.md](wardley.md) | Full rewrite of wardley.dart. parseWardley now captures the complete grammar (pipelines, decorators, inertia, notes, … |
| **eventModeling** | — | 🟡 | 11 | 0 | ✅ | [eventModeling.md](eventModeling.md) | Rewrote eventmodeling.dart to match upstream db.ts + renderer.ts. Parser now handles tf/timeframe + rf/resetframe, lo… |
| **pie** | — | 🟢 | 12 | 2 | ✅ | [pie.md](pie.md) | 11 of 13 discrepancies fully resolved; 1 partial (palette correct for default theme, dynamic theming deferred) and 1 … |
| **radar** | — | 🟢 | 14 | 1 | ✅ | [radar.md](radar.md) | All 14 visual discrepancies fixed; #15 (strict header) intentionally left lenient. cScale colors are the precomputed … |
| **flowchart** | dagre, elk, tidy-tree | 🟢 | 9 | 0 | ✅ | [flowchart.md](flowchart.md) | All 9 discrepancies fixed in flow_layout.dart; dart analyze on flowchart/ is clean (the 6 remaining package errors ar… |
| **er** | — | 🟢 | 12 | 0 | ✅ | [er.md](er.md) | All 12 actionable discrepancies fixed (13th was a no-op confirmation). Default-theme constants computed inline: terti… |
| **quadrant** | — | 🟢 | 10 | 0 | ✅ | [quadrant.md](quadrant.md) | Rewrote quadrant.dart to mirror upstream QuadrantBuilder: 500x500 coordinate space with padding 5, calculateSpace-der… |
| **packet** | — | 🟢 | 8 | 0 | ✅ | [packet.md](packet.md) | All 8 discrepancies (1 high, 3 medium, 4 low) resolved in layoutPacket. Rewrote constants and layout to match upstrea… |

## Deferred items (30) — need shared changes or are non-default-theme/niche

These were intentionally NOT done in the per-diagram pass because they require editing shared infrastructure (IR primitives, `MermaidTheme` fields, vendored dagre) or only affect non-default themes / unsupported config.

| Diagram | Deferred item | Reason |
|---|---|---|
| sequence | #4 Theme-driven sequence colors | Requires new MermaidTheme fields consumed in layout (forbidden); inline constants already equal the default theme exactly, only non-default themes would differ. |
| sequence | #12 mirrorActors/bottomMarginAdj configurable | Requires threading sequence config that is not yet exposed; default behavior matches default config. |
| sequence | #5 Message line stroke width | Parity doc was incorrect: upstream .messageLine0/1 is stroke-width:1.5, which Dart already uses; no change needed. |
| classDiagram | Note attach edge minLen 0 (keep note adjacent to class) | Requires fixing zero-length-edge crash in vendored vendor/dagre, which is outside the class_diagram source dir and forbidden to edit. |
| stateDiagram | Self-transition routing is bespoke | Optional/cosmetic; routing self-edges through dagre is a layout change, not a default-theme value mismatch — left as acceptable approximation. |
| pie | Theme-derived palette (dynamic recolor for custom/dark themes) | Requires adding pie1..pie12 color fields to shared MermaidTheme, forbidden by hard rules 1-3. Inlined exact default-theme hex instead, so default theme matches; custom themes won't recolor. |
| pie | donutHole / legendPosition / highlightSlice config | Requires plumbing PieDiagramConfig through pie_model/pie_parser. Rendered defaults (donutHole=0, legendPosition=right, no highlight) already match upstream defaults; configurable variants deferred. |
| gantt | Fixed plot width vs responsive width | Applied as fixed 1050px (upstream 1200 fallback minus paddings) for correct proportions; true container-offsetWidth responsiveness is out of scope for an intrinsically-sized render with no DOM container. |
| mindmap | #1 Layout algorithm (cose-bilkent) | Deliberate port choice: deterministic radial tree, no force simulation. Documented in file header. |
| mindmap | #6 Theme-driven colors | MermaidTheme exposes no cScale/git fields and rules forbid adding them; default-theme constants inlined, so non-default themes are not reflected. |
| mindmap | #13 Root centering | Cosmetic; root pinned at origin then scene fit to bounds, and layout already deviates. |
| requirement | classDef/class/style directive support with per-node cssStyles + colorIndex color cycling | Full styling application is a larger feature; parser now tolerates (skips) these directives instead of throwing. Upstream default theme has no borderColorArray so default rendering is unaffected; applying user cssStyles would need broader style-parsing infra. |
| c4 | #3 Person 48x48 avatar PNG | Requires a raster-image IR primitive in scene.dart which is forbidden to edit; approximated with a 48px head+shoulders silhouette and reserved image band so spacing matches. |
| c4 | #19 First-straight/rest-curved relation rendering | Low/cosmetic; with the new grid + rect-edge intersection all rels are single straight segments, an acceptable approximation of upstream's mostly-straight rels. |
| gitGraph | parallelCommits mode + showBranches/showCommitLabel toggles | Read from gitGraph diagram config, which is not threaded into layoutGitGraph(graph, measurer, theme); wiring it would change the public layout API / registry call (forbidden outside git/). Defaults used. |
| gitGraph | RL direction | Folded into LR; a true right-to-left mirror needs a horizontal-flip pass; low value, kept simple. |
| gitGraph | commit-label-bkg 50% opacity | Scene IR Fill carries only an opaque color (no alpha/opacity), so the semi-transparent label background is approximated with a solid #ffffde rect; faithful match needs a shared IR Fill-opacity primitive. |
| sankey | mix-blend-mode:multiply on link overlaps | Needs a blend-mode field on the shared IR/backends, which are read-only here. |
| sankey | True gradient-stroked link paths + 4px outlined-label stroke halo | Stroke has no gradient and SceneText has no stroke in scene.dart (read-only); approximated via Fill gradient bands and a background-colored text copy. |
| radar | Header keyword radar accepted (non-spec leniency) | Kept radar as a lenient alias alongside radar-beta to preserve existing behavior/tests (hard rule 4); it is not a visual discrepancy. |
| treemap | Config support (nodeWidth/Height, padding, showValues, valueFormat, font sizes from treemap: block) | No config infrastructure in this port; applied upstream defaults inline (canvas 960x500, diagramPadding 8, showValues on, valueFormat ',') but a user treemap config block / custom valueFormat strings need shared config plumbing that is out of scope. |
| kanban | 4 (icon rendering) | No icon/raster/glyph primitive in scene IR; adding one is a shared-IR change outside this diagram. icon is parsed and stored on KanbanTask for later wiring. |
| kanban | 5 (apply style/class overrides) | Applying per-node fill/stroke/class overrides needs a node-style override channel into layout plus robust id resolution; directives are parsed and skipped but the visual override is not applied. Low impact on default corpus. |
| architecture | Force-directed fcose layout algorithm | A seeded fcose constraint solver is a large layout subsystem; kept the deterministic grid BFS but widened cell pitch to iconSize+nodeSeparation and added align support to approximate spacing. Documented grid as intentional approximation. |
| architecture | Full icon pack / iconify fallback | Shipping the complete architecture + iconify icon packs needs new pack assets registered outside the architecture/ dir (icon_registry/builtin pack). Expanded aliases and honoured explicit prefix:name refs; cog remains last-resort fallback. |
| venn | No hand-drawn (rough.js) look | Requires a rough/hachure rendering primitive in the shared IR (forbidden by hard-rule 3); out of scope. |
| railroad | No comment/ellipse node | The single EBNF parser we use never emits a comment node; adding one would be unreachable dead code. |
| railroad | ABNF/PEG grammar variants unsupported | Requires new grammars/detectors and edits to detect.dart, which is off-limits; large out-of-scope parser work. |
| railroad | Choice/optional/repetition arcs are cubic Beziers vs true quarter-circle arcs | Shared IR PathCommand set has no ArcTo primitive; adding one is a forbidden shared change. |
| railroad | Repetition separator not rendered | RailroadRepetition AST has no separator child and the EBNF parser does not capture one; needs AST+parser changes producing nothing for current inputs. |

## Pipeline status

1. ✅ **Analyze** — 28 docs, 349 discrepancies logged.
2. ✅ **Implement** — per-diagram fixes applied; full gate green.
3. ✅ **Verify** — all 28 rendered to PNG and checked for structural fidelity; full gate green.

## Cross-cutting follow-ups (would unlock deferred items)

- **Raster-image IR primitive** → C4 person avatar, any icon-as-image.
- **Theme field expansion** (sequence note/actor-line, venn1..8, journey/timeline palettes, pie1..12, etc.) → correct rendering under non-default themes (default theme already matches via inlined constants).
- **Zero-length-edge support in vendored dagre** → class-diagram note adjacency, others.
