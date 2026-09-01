# Mermaid parity review findings — batch 01

Captured from the first Lavish feedback send. Mermaid.js is the reference and
the Flutter render is the review target unless noted otherwise.

## Confirmed differences

- None remaining from this batch.

## Resolved in this branch

- `curated-block`: spanning groups now participate in sibling-width
  equalization, and their children expand with them.
- `curated-handdrawn`: edge paths remain sketchy while their arrow markers stay
  crisp, so the `Debug` return marker remains visible at the diamond boundary.
- `curated-kanban` and `curated-radar`: updated the shared default color scale
  to Mermaid 11.17.2 values.
- `curated-railroad`: generic monospace is retained for Flutter platform font
  resolution, and the screenshot harness loads a deterministic monospace font
  instead of Flutter's solid-block Ahem test glyphs.
- `curated-treemap`: ported D3's golden-ratio squarification and padding stack;
  `API` and `DB` now use the same side-by-side split as Mermaid.js.
- `curated-venn`: singleton labels now sit in their exclusive regions on the
  same baseline as the union label.
- `upstream-c4-05`: deployment boundaries are solid and reserve measured space
  for their complete headers.
- `upstream-class-11`: disjoint namespaces no longer overlap and relation-label
  backgrounds are opaque.
- `upstream-er-03`: table-cell text now has balanced horizontal padding.

## Source-aligned differences needing font-metric review

- `curated-subgraphs`: a pinned Mermaid 11.17.2 CLI capture does not reproduce
  the reported padding defect. Mermaid.js uses a cluster at `y=8`, height 124;
  Dart uses `y=8`, height 121, and both titles start at `y=8`. Dart's member
  boxes sit slightly higher because Flutter's text line height is shorter than
  Mermaid's HTML-label line height; this is a shared typography question, not
  a cluster-padding constant.
- `curated-ishikawa`: Mermaid 11.17.2 uses the same 20px horizontal and 2px
  vertical cause-label padding already used by Dart. The regenerated labels
  have visible inset and no longer touch their boxes.
- `curated-wardley`: both renderers request bold axis labels; the remaining
  visual difference is in font measurement or rasterization rather than the
  diagram style constants. The regenerated Flutter axis titles are bold.

## Reference limitations or acceptable differences

- `curated-math`: looks correct; Flutter is larger.
- `curated-architecture`: Flutter's rounded corners look preferable, while
  Mermaid.js uses hard corners.
- `curated-cynefin`: Mermaid.js does not render the source, so it cannot serve
  as a parity reference for this case.
- `curated-railroad`: Mermaid.js does not render the source, so the diagram
  geometry still cannot be judged as parity against this reference case.
