# flowchart — parity analysis
**Status:** full-parity
**Last analyzed:** TODO-date

## How mermaid.js implements it
- Entry/render: `flowchart/flowRenderer-v3-unified.ts:draw` builds `LayoutData` from `flowDb.getData()`, selects the registered layout algorithm (`getRegisteredLayoutAlgorithm(layout)`), and calls the unified `rendering-util/render.ts`. `nodeSpacing`/`rankSpacing` default 50; markers `['point','circle','cross']`; `diagramPadding` default 8 (`setupViewPortForSVG`).
- Layout default is **dagre** (`rendering-util/layout-algorithms/dagre/index.js`). `layout: elk` for flowchart logs a warning and **falls back to dagre** (flowchart-elk moved to an external package in v11 — see flowRenderer-v3-unified.ts:36).
- Node sizing lives in `rendering-util/rendering-elements/shapes/*` via `labelHelper` (`util.ts`): `bbox` from the rendered label, `halfPadding = node.padding/2`. `node.padding` for a vertex is `config.flowchart?.padding || 8`, but the schema default `flowchart.padding` is **15**, so effective padding = 15 (`flowDb.ts:1049`). Subgraph padding = 8 (`flowDb.ts:1125`).
- Per-shape sizing (key ones):
  - `squareRect.ts` (`[text]`, and default bare node): `labelPaddingX = padding*2 = 30`, `labelPaddingY = padding = 15`; `drawRect.ts` → `totalWidth = bbox.w + 2*labelPaddingX = bbox.w + 60`, `totalHeight = bbox.h + 30`.
  - `roundedRect.ts` (`(text)`): rx=ry=`themeVariables.radius ?? 5`, `labelPaddingX/Y = padding = 15` → `bbox.w + 30`, `bbox.h + 30`.
  - `stadium.ts`: `h = bbox.h + padding`, `w = bbox.w + h/4 + padding`, radius `h/2`.
  - `question.ts` (diamond): `w=bbox.w+padding`, `h=bbox.h+padding`, `s=w+h`; intersect offset −0.5,−0.5.
  - `hexagon.ts`: `h=bbox.h+padding`, `m=h/4`, `w=bbox.w+2m+padding`.
  - `circle.ts`: `radius = bbox.w/2 + halfPadding`.
- Theme/styles: `flowchart/styles.ts` — node fill `mainBkg`, stroke `nodeBorder`, stroke-width `strokeWidth ?? 1`; edges `lineColor` width `strokeWidth ?? 2`; edge label bg `edgeLabelBackground` with **opacity 0.5** rect; cluster fill `clusterBkg`/border `clusterBorder`; title 18px `textColor` (`.flowchartTitleText`).
- Edges: default curve **basis** (`config.schema.yaml`), per-edge `interpolate` via `linkStyle … interpolate`. Markers defined in `markers.js`: point = path `M 0 0 L 10 5 L 0 10 z` (10×10, refX 5, markerUnits scale with strokeWidth); circle and cross variants; thick stroke for `==>`, dotted dash for `-.->`.
- Diagram title via `utils.insertTitle` (above content, 18px, anchored middle, `titleTopMargin` default 0).

## How mermaid_dart implements it
- `flow_layout.dart:layoutFlowchart` measures labels, sizes shapes, runs the vendored dagre, routes edges (curveBasis port), emits `RenderScene`. Constants: `_nodePadding=15`, `_diagramPadding=8`, `_clusterPadding=8`, `_nodeSpacing=50`, `_rankSpacing=50`, `_wrappingWidth=200` (all match upstream defaults).
- Shapes: `_Shape.forNode` (`flow_layout.dart:969`) ports the upstream shape math. Notably rect/plain use `lw + 2*p`/`lh + 2*p` (= +30/+30); rounded rx=5; stadium, cylinder, circle, doubleCircle, question/diamond, hexagon, lean/trapezoid, asymmetric, plus the full v11 `@{ shape: }` family (document, triangle, card, hourglass, fork/join, crossed-circle, etc.).
- Intersections ported from upstream `intersect/*` (`_intersectRect`, `_intersectEllipse`, `_intersectPolygon`, `_intersectLine`).
- Edges: `_resolveEdgeStyle` — normal width 2.0, thick 3.5, dotted dash `[3,3]`; curve dispatch `_edgeCurve` (basis default; linear/step/catmull-rom families). Markers `_marker`: point triangle (len 10, half-width 4, shorten 9), circle r5, cross. Edge label bg rect rx2 fill `edgeLabelBackground` (no opacity).
- Subgraphs/clusters: compound dagre nodes; per-subgraph `direction` handled by recursive isolated-cluster layout; edges targeting subgraph ids routed via a representative member and clipped to the cluster rect (`_dropInsideRect`). Self-loops routed manually (`_selfLoop`).
- Title via `layoutFlowchart` — bold 700 style at `theme.fontSize`, placed above content.
- Engines: `layout_engines.dart` — `tidy-tree` (Reingold–Tilford over BFS forest, no clusters) and `elk` (keeps dagre placement but routes edges orthogonally). Selected by `engine` arg.

## Discrepancies
1. `[open] (high) Square/plain rect X-padding is half of upstream`
   - Upstream `[text]` and bare-default nodes use `labelPaddingX = padding*2 = 30` → width `bbox.w + 60`. Our `rect`/`plain` use `lw + 2*15 = lw + 30`. Rectangles render ~30px narrower than mermaid.js; cascades into dagre spacing and overall size.
2. `[open] (high) layout: elk should fall back to dagre, not change routing`
   - Upstream v11 flowchart ignores elk (external package) and renders with dagre + curveBasis edges. Our `elk` engine reroutes every edge as orthogonal Manhattan paths and uses `linear` curve — a visibly different diagram from mermaid.js.
3. `[open] (medium) Edge-label background lacks 0.5 opacity`
   - `styles.ts` `.edgeLabel rect { opacity: 0.5 }`. Our `_edgeLabelGroup` fills the bg rect at full opacity, so labels over edges look heavier/more opaque than upstream.
4. `[open] (medium) Diagram title size/weight differs`
   - Upstream `.flowchartTitleText` is fixed 18px, normal weight, `textColor`. Our title uses `theme.fontSize` (≈16) with `fontWeight:700` and `theme.titleColor`. Title is smaller, bolder, and possibly a different color.
5. `[open] (medium) Cluster title is vertically inside the cluster body, not in a reserved title band`
   - Upstream reserves a title band and offsets node area; our isolated-cluster `titleBand` adds only `titleSize.height + 4`, and non-isolated clusters extend the rect upward by `titleSize.height` only — title-to-content gap and top padding can differ from upstream `rectWithTitle` spacing.
6. `[open] (low) Stadium/question/hexagon use padding (15) where upstream uses the same — OK, but circle uses full padding not halfPadding`
   - Upstream `circle.ts` radius = `bbox.w/2 + halfPadding` (halfPadding = 7.5). Our `_CircleShape` uses `max(lw,lh)/2 + p` (p=15) and also takes `max(w,h)` instead of just width. Circles are larger and sized off height too.
7. `[open] (low) doubleCircle outer radius uses full padding + uses max(w,h)`
   - Same root as #6 (`circle.ts` uses halfPadding and width-only); our doubleCircle inherits the larger sizing.
8. `[open] (low) Marker geometry approximate`
   - Upstream point marker is `M 0 0 L 10 5 L 0 10 z` scaled by stroke-width (markerUnits), with refX 5 / margin variants (refX 11.5). Our fixed triangle (half-width 4, shorten 9) is close but not stroke-width-scaled, so thick edges get a proportionally smaller head than upstream.
9. `[open] (low) tidy-tree engine has no upstream equivalent`
   - mermaid.js flowchart only ships dagre (and elk→dagre fallback). `tidy-tree` produces a layout mermaid.js never renders; harmless if unused, but cannot be "parity" against upstream.

## Proposed fixes
1. In `flow_layout.dart:_Shape.forNode`, give `rect`/`plain` width `lw + 4*p` (60) while keeping height `lh + 2*p`, matching `squareRect.ts` labelPaddingX*2.
2. In `flow_layout.dart:_layoutGraph`, treat `engine == 'elk'` as dagre (drop `orthogonalEdges`/`linear`); keep elk only as an explicit opt-in, defaulting flowchart to dagre to mirror the v11 fallback.
3. In `flow_layout.dart:_edgeLabelGroup`, set the bg rect `Fill` to `edgeLabelBackground` at 0.5 opacity (or fade the color) to match `styles.ts`.
4. In `flow_layout.dart:layoutFlowchart` title block, use fixed 18px, `fontWeight:400`, `theme.textColor` to match `.flowchartTitleText`.
5. In `flow_layout.dart` cluster emission, reserve a proper title band (height + label gap) consistent with upstream `rectWithTitle`, applying the same offset for both isolated and compound clusters.
6. In `_Shape.forNode` circle case, use `lw/2 + p/2` (halfPadding) and base radius on width only, per `circle.ts`.
7. In `_Shape.forNode` doubleCircle case, apply the same halfPadding/width-only sizing as fix 6 before adding the gap.
8. In `flow_layout.dart:_marker`, scale the point triangle by `style.width/2` (markerUnits-equivalent) and align lengths with the `M 0 0 L 10 5 L 0 10 z` path.
9. Document `tidy-tree` as a non-upstream extension; ensure flowchart never selects it implicitly (only via explicit config).

## Implementation log
1. Done — `_Shape.forNode` rect/plain now `lw + 4*p` width (= bbox.w + 60), height unchanged `lh + 2*p`, matching `squareRect.ts` (labelPaddingX = padding*2) + `drawRect.ts` (total = bbox + 2*labelPadding).
2. Done — `engine == 'elk'` is now a no-op alias for dagre (mirrors v11 fallback in flowRenderer-v3-unified.ts:36). Removed the orthogonal rerouting + `linear` curve branch; elk keeps dagre placement with default basis curves. `orthogonalRoute` in layout_engines.dart is left intact (still exported) but no longer called by flowchart.
3. Done — edge-label bg rect now multiplies the resolved `edgeLabelBackground` alpha by 0.5 (CSS `opacity: 0.5` semantics), so default 0xcce8e8e8 → ~0.4 effective alpha.
4. Done — diagram title now fixed 18px, fontWeight 400, `theme.textColor` (was theme.fontSize/700/titleColor), matching `.flowchartTitleText`.
5. Done — cluster title placed flush at `rect.top` (subGraphTitleMargin.top default 0) for both compound and isolated clusters; `titleBand` reduced from `titleSize.height + 4` to `titleSize.height`, matching upstream `clusters.js` label translate.
6. Done — circle radius now `lw/2 + p/2` (halfPadding, width-only) per `circle.ts`.
7. Done — doubleCircle inner radius now `lw/2 + p/2 + gap` (same halfPadding/width-only basis as #6).
8. Done — point marker corrected to upstream `userSpaceOnUse` geometry: 8px length (10-unit viewBox → 8px marker), half-height 4px, path shorten 8. NOTE: the original proposed fix ("scale by stroke-width") was inaccurate — upstream markers use `markerUnits: userSpaceOnUse` and do NOT scale with stroke width; the real gap was marker length (10 → 8). Cross/circle markers left unchanged (different viewBoxes, not in scope).
9. Done — documented `tidy-tree` as a Dart-only extension; confirmed it is only reachable via explicit `engine: 'tidy-tree'` (default 'dagre' and the elk alias never select it). No behavior change needed.

## Layout engines
- **dagre (default, primary parity target):** Upstream `rendering-util/layout-algorithms/dagre/index.js` runs graphlib dagre with `rankdir` from direction, `nodesep`/`ranksep` = 50, compound clusters for subgraphs, and edge points from dagre then clipped to shape intersect. Our vendored `dart_dagre` is driven the same way (`flow_layout.dart` step 3–5), with the same nodeSep/rankSep and intersect clipping, plus manual self-loops and representative-member routing for edges to subgraph ids (mirrors `adjustClustersAndEdges`). This is the closest-parity path; remaining gaps are the rect-padding (#1) and cluster-title-band (#5) sizing differences feeding dagre, not the algorithm itself. Edge curve = basis on both sides.
- **elk:** Upstream flowchart does **not** use elk in v11 — `layout: elk` warns and falls back to dagre (flowRenderer-v3-unified.ts:36); there is no orthogonal ELK routing in core mermaid flowcharts. Our `elk` engine instead keeps the dagre placement but rewrites edges as orthogonal Manhattan paths with `linear` interpolation (`layout_engines.dart:orthogonalRoute`). This is a structural divergence (discrepancy #2): selecting elk yields a diagram mermaid.js would render with smooth basis curves.
- **tidy-tree:** No upstream counterpart for flowchart (mermaid.js ships only dagre for `graph`/`flowchart`). Our implementation (`layout_engines.dart:tidyTreeLayout`) is a Reingold–Tilford/Walker tidy tree over a BFS spanning forest, ignoring clusters (disabled when subgraphs exist) and routing straight edges. Cannot be assessed for parity; treat as a Dart-only extension (discrepancy #9). Sibling/level gaps reuse nodeSpacing/rankSpacing (50/50).
