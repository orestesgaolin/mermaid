# C4, ER, and XY configuration support

Compared with the checked-in Mermaid.js schema and renderers at the current
upstream revision. Both frontmatter `config:` and `%%{init}%%` use the shared
configuration resolver; focused tests cover both forms.

## C4

Supported by `C4Config` and the scene layout:

- `diagramMarginX`, `diagramMarginY`
- `c4ShapeMargin`, `c4ShapePadding`
- `width`, `height`
- `c4ShapeInRow`, `c4BoundaryInRow`
- `nextLinePaddingX`
- `wrap`
- every per-variant `*FontSize`, `*FontFamily`, and `*FontWeight` key
- every per-variant `*_bg_color` and `*_border_color` key
- `boundaryFont*` and `messageFont*`

`boxMargin` and `wrapPadding` are present in the schema but are not read by
Mermaid.js's active C4 renderer. They are therefore intentionally inert here
too. `useMaxWidth` controls the browser SVG's responsive width; it has no
intrinsic meaning in a sized `RenderScene` and remains a backend concern.

`C4Node.styleKey` preserves the source variant while the existing `kind` keeps
the public geometry categories. This lets `SystemDb`, `ContainerDb_Ext`, and
the other DB/Queue variants resolve their exact upstream font and color keys.
The optional field keeps source compatibility for callers that construct nodes.

## ER

Supported:

- `entityPadding`: vertical space added once to each header and attribute row
- `diagramPadding`: horizontal space added once per attribute column and twice
  around an attribute-less entity label
- `minEntityWidth`, `minEntityHeight`: minimum rendered entity dimensions
- `nodeSpacing`, `rankSpacing`: Dagre spacing on and between ranks
- `titleTopMargin`: space between the title and diagram content

The outer scene margin remains 8, matching the unified renderer's viewport
padding. It is deliberately separate from `er.diagramPadding`, which the
active `erBox` renderer uses for entity internals.

Mermaid.js 11.17.2 render evidence confirms that omitting `diagramPadding` and
setting it explicitly to 20 produce the same 129.53125 x 85.5 entity and
145.53125 x 101.5 SVG viewBox. See
`build/high_medium_evidence/er-upstream-padding.{html,png,txt}`.

`layoutDirection` is not read by Mermaid.js's active unified renderer; diagram
syntax remains the direction source. The active `erBox` renderer also derives
stroke, fill, and text styles from node styles and theme variables rather than
the legacy ER `stroke`, `fill`, and `fontSize` schema keys. Those keys remain
intentionally inert here.

## XY chart

Supported by `XyChartConfig`:

- `width`, `height`, `titleFontSize`, `titlePadding`, `showTitle`
- `chartOrientation`, `plotReservedSpacePercent`
- `showDataLabel`, `showDataLabelOutsideBar`

Supported independently for `xAxis` and `yAxis`:

- `showLabel`, `labelFontSize`, `labelPadding`, `labelRotation`
- `showTitle`, `titleFontSize`, `titlePadding`
- `showTick`, `tickLength`, `tickWidth`
- `showAxisLine`, `axisLineWidth`

Mermaid.js only applies `labelRotation` while drawing the bottom axis. Its left
and top axis drawing paths hard-code zero rotation. The Dart renderer preserves
that behavior. Values outside the schema range of -90 through 90 fall back to
zero.
