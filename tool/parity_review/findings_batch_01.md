# Mermaid parity review findings — batch 01

Captured from the first Lavish feedback send. Mermaid.js is the reference and
the Flutter render is the review target unless noted otherwise.

## Confirmed differences

No unresolved differences remain from the first two visual feedback passes.

## Resolved in this branch

- `curated-block`: spanning groups now participate in sibling-width
  equalization, and their children expand with them.
- `curated-handdrawn`: edge paths remain sketchy while their arrow markers stay
  crisp, so the `Debug` return marker remains visible at the diamond boundary.
- `curated-kanban` and the `curated-radar` series: updated the shared default
  color scale to Mermaid 11.17.2 values.
- `curated-railroad`: generic monospace is retained for Flutter platform font
  resolution, and the screenshot harness loads a deterministic monospace font
  instead of Flutter's solid-block Ahem test glyphs.
- `upstream-c4-05`: deployment boundaries are solid and reserve measured space
  for their complete headers.
- `upstream-er-03`: table-cell text now has balanced horizontal padding.
- `curated-subgraphs`: cluster titles now use Mermaid's HTML-label line-height
  baseline without changing the cluster layout band.
- `curated-ishikawa`: boxed cause labels use Mermaid's middle-baseline offset.
- `curated-radar`: body-level titles are parsed and `Skills` is rendered.
- `curated-treemap`: the effective 1000×400 default layout restores the
  side-by-side `UI` / `State` row as well as the `API` / `DB` row.
- `curated-venn`: singleton labels share the union baseline and the title uses
  Mermaid's stylesheet-resolved 32px size.
- `upstream-class-11`: namespaces do not overlap, relation-label backgrounds
  are opaque, and cross-namespace relations enter `Circle` and `Square`
  vertically.
- `upstream-flowcharts-07`: legacy Font Awesome markers are consumed instead
  of appearing as literal `fa:fa-*` label text.

## Source-aligned differences needing font-metric review

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

## Deferred to the next session

- Sankey needs a dedicated visual pass; do not treat its current capture as
  accepted parity.
