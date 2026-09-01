# Mermaid parity review findings — batch 01

Captured from the first Lavish feedback send. Mermaid.js is the reference and
the Flutter render is the review target unless noted otherwise.

## Confirmed differences

- `curated-subgraphs` (`packages/mermaid_samples:subgraphs`)
  - The sibling cluster-title baselines do not align with Mermaid.js.
- `curated-ishikawa` (`packages/mermaid_samples:ishikawa`)
  - `Technology` and `People` use a different vertical text baseline from
    Mermaid.js even though the box-padding constants match.
- `curated-radar` (`packages/mermaid_samples:radar`)
  - Flutter omits the diagram title, `Skills`.
- `curated-treemap` (`packages/mermaid_samples:treemap`)
  - `API` and `DB` now match, but Flutter stacks `UI` and `State` vertically;
    Mermaid.js places them side by side.
- `curated-venn` (`packages/mermaid_samples:venn`)
  - Flutter renders `Skills overlap` much smaller and lighter than Mermaid.js.
- `upstream-class-11`
  (`packages/mermaid_core/test/fixtures/upstream_class/11.mmd`)
  - Relation arrows enter `Circle` and `Square` from the side in Flutter;
    Mermaid.js routes them into the top edge.

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

## Partially resolved in this branch

- `curated-treemap`: ported D3-style squarification and padding; `API` and `DB`
  now match, but the `UI` / `State` row decision is still wrong.
- `curated-venn`: singleton labels now share the union-label baseline, but the
  title typography is still incorrect.
- `upstream-class-11`: disjoint namespaces no longer overlap and relation-label
  backgrounds are opaque, but relation ports still differ.

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
