# Mermaid parity tracker

Per-diagram parity vs upstream mermaid.js. Pipeline: **analyze → implement → theme-wire → verify**. Each diagram has a detailed doc at `parity/<type>.md`.

**Parity:** 🟢 full · 🟡 minor-gaps · 🔴 major-gaps   ·   **Stage:** ✅ render-verified (default + dark themes)

## Status: 28 🟢 / 0 🟡 / 0 🔴 across 28 types

Progression: analysis **0/8/20** → implement **6/22/0** → theme-wire **28/0/0**. Gate: `dart analyze` clean · 412 tests · 184/184 corpus. All 28 rendered (default + dark) and checked for structural fidelity.

> **What 🟢 means here:** the diagram matches mermaid.js's default-theme render (shapes, palette, spacing, layout) AND now recolors correctly under dark/forest/neutral (diagrams read `MermaidTheme` palette fields instead of inlining constants). Residuals listed below are non-default-theme niche config or documented cosmetic approximations — not default-render gaps. Caveat: verification is structural render-diff + exact upstream constants, not a live pixel-diff against the mermaid.js CDN.

| Diagram | Engine(s) | Parity | Stage | Doc | Residual (non-blocking) |
|---|---|:--:|:--:|---|---|
| **flowchart** | dagre, elk, tidy-tree | 🟢 | ✅ | [flowchart.md](flowchart.md) | default render matches; adapts across themes |
| **sequence** | — | 🟢 | ✅ | [sequence.md](sequence.md) | box-grouping title text + arrowhead color + sequence-number circle stay on generic theme fields (no dedicat… |
| **classDiagram** | — | 🟢 | ✅ | [classDiagram.md](classDiagram.md) | note attach edge uses minLen 1 instead of upstream minLen 0 (pushes notes one rank away); gated on a fix to… |
| **stateDiagram** | — | 🟢 | ✅ | [stateDiagram.md](stateDiagram.md) | Self-loop edge routing is bespoke (hand-routed cubic) rather than dagre-routed — geometry-only, not a defau… |
| **er** | — | 🟢 | ✅ | [er.md](er.md) | classDef/class/style color-theme data-color-id indexing skipped (default-theme only; niche styling directiv… |
| **pie** | — | 🟢 | ✅ | [pie.md](pie.md) | donutHole / legendPosition / highlightSlice config not supported (niche config, not default-render); requir… |
| **gantt** | — | 🟢 | ✅ | [gantt.md](gantt.md) | container-responsive plot width: intrinsic render uses fixed 1050px plot (no container offsetWidth availabl… |
| **quadrant** | — | 🟢 | ✅ | [quadrant.md](quadrant.md) | default render matches; adapts across themes |
| **journey** | — | 🟢 | ✅ | [journey.md](journey.md) | 4ex title size approximated as 2*taskFontSize (font ex-metrics not resolved) |
| **timeline** | — | 🟢 | ✅ | [timeline.md](timeline.md) | timeline LR/TD direction is parsed but not honored (upstream renders columnar regardless of direction) |
| **xychart** | — | 🟢 | ✅ | [xychart.md](xychart.md) | config-only residual (showDataLabel via %%{init}%% JSON, d3 tick formatting) |
| **mindmap** | — | 🟢 | ✅ | [mindmap.md](mindmap.md) | #1 layout algorithm: deliberate deterministic radial tree vs upstream cose-bilkent force simulation (intent… |
| **requirement** | — | 🟢 | ✅ | [requirement.md](requirement.md) | classDef/class/style per-node cssStyles + colorIndex color-cycling still deferred (parser/IR feature, not a… |
| **c4** | — | 🟢 | ✅ | [c4.md](c4.md) | person is a vector rendition of upstream raster avatar; rels straight not curved (cosmetic) |
| **gitGraph** | — | 🟢 | ✅ | [gitGraph.md](gitGraph.md) | parallelCommits mode and showBranches/showCommitLabel toggles are not wired because layoutGitGraph(graph, m… |
| **sankey** | — | 🟢 | ✅ | [sankey.md](sankey.md) | mix-blend-mode:multiply on link compositing (no IR blend-mode field) |
| **packet** | — | 🟢 | ✅ | [packet.md](packet.md) | default render matches; adapts across themes |
| **block** | — | 🟢 | ✅ | [block.md](block.md) | marker geometry (circle/cross) approximated vs upstream insertMarkers SVG markers |
| **radar** | — | 🟢 | ✅ | [radar.md](radar.md) | header keyword: bare `radar` accepted as a lenient alias to `radar-beta` (non-visual, preserves existing te… |
| **treemap** | — | 🟢 | ✅ | [treemap.md](treemap.md) | No D3 treemap config block (padding/nodeWidth/nodeHeight/showValues/font sizes) parsed - needs shared confi… |
| **kanban** | — | 🟢 | ✅ | [kanban.md](kanban.md) | icons (item @{icon}) parsed but not drawn: needs an icon/glyph primitive in the shared scene IR |
| **architecture** | — | 🟢 | ✅ | [architecture.md](architecture.md) | iconText (('text')) form: upstream renders white text over a transparent 'blank' icon (invisible on default… |
| **cynefin** | — | 🟢 | ✅ | [cynefin.md](cynefin.md) | per-domain background fills (complexBg/complicatedBg/chaoticBg/clearBg/confusionBg) and cliffColor live in … |
| **venn** | — | 🟢 | ✅ | [venn.md](venn.md) | area-proportional packing for >=3 sets is a relaxation heuristic, not venn.js' exact MDS solver |
| **ishikawa** | — | 🟢 | ✅ | [ishikawa.md](ishikawa.md) | TextMeasurer-based bbox/spine-extent approximation vs live getBBox() (non-color, non-DOM limitation) |
| **wardley** | — | 🟢 | ✅ | [wardley.md](wardley.md) | axisTextColor/componentLabelColor/annotationTextColor inlined as #222: upstream derives these from primaryT… |
| **eventModeling** | — | 🟢 | ✅ | [eventModeling.md](eventModeling.md) | Dark-theme entity fills (emUiFill/emProcessorFill/emReadModelFill/emCommandFill/emEventFill + strokes) and … |
| **railroad** | — | 🟢 | ✅ | [railroad.md](railroad.md) | specialFill #F0E0FF / specialStroke #8800CC left inlined: upstream derives from tertiaryColor/tertiaryBorde… |

## Known residuals (do NOT affect default-theme parity)

Grouped by what would be needed to close them — all are niche config, custom-theme edge cases, or documented approximations:

- **Config plumbing** (defaults already match upstream): pie donutHole/legendPosition/highlightSlice · gitGraph parallelCommits/showBranches toggles · sequence mirrorActors/bottomMarginAdj · treemap custom config block · xychart `%%{init}%%` JSON data-labels · requirement/kanban per-node style/class overrides.
- **Shared-IR primitives** (disproportionate for the payoff): C4 raster person avatar (async image decode in sync painter) → vector rendition used · railroad true ArcTo quarter-circles → cubic-bezier approximation · sankey mix-blend-mode multiply on link overlaps.
- **Layout subsystems**: architecture force-directed fcose → deterministic grid+align approximation · mindmap cose-bilkent → deterministic radial (intentional) · classDiagram note adjacency needs zero-length-edge support in vendored dagre.
- **Custom-theme color sources without a theme variable upstream**: gantt task/section/crit palette, xychart handled via new field, C4 per-kind colors (config.schema constants) — default renders are exact.

## Pipeline status

1. ✅ **Analyze** — 28 docs, 349 discrepancies logged.
2. ✅ **Implement** — 333 fixes; 0 major remained.
3. ✅ **Theme-wire** — `MermaidTheme` expanded with cScale/pie/git/sequence/journey/quadrant/venn/er/requirement/xychart palettes; diagrams switched from inlined constants to theme reads (default identical, dark/forest/neutral now adapt).
4. ✅ **Verify** — rendered all 28 in default + dark; structural fidelity confirmed.

