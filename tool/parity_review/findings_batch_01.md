# Mermaid parity review findings — batch 01

Captured from the first Lavish feedback send. Mermaid.js is the reference and
the Flutter render is the review target unless noted otherwise.

## Confirmed differences

- `curated-subgraphs` (`packages/mermaid_samples:subgraphs`)
  - `Stage One` is too close to the top edge.
  - There is too little padding around the `Stage One` / `Stage Two` labels and
    between the lower boxes and the subgraph boundary.
- `curated-ishikawa` (`packages/mermaid_samples:ishikawa`)
  - `Technology` and `People` have insufficient padding.
  - Their text baseline is too low and touches the bottom edge.
- `curated-wardley` (`packages/mermaid_samples:wardley`)
  - Mermaid.js renders `Visibility` and `Evolution` in bold.
- `curated-handdrawn` (`packages/mermaid_samples:handdrawn`)
  - The edge from `Debug` to `Is it working?` is partially hidden behind the
    diamond.

## Resolved in this branch

- `curated-block`: spanning groups now participate in sibling-width
  equalization, and their children expand with them.
- `curated-kanban` and `curated-radar`: updated the shared default color scale
  to Mermaid 11.17.2 values.
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

- `curated-ishikawa`: Mermaid 11.17.2 uses the same 20px horizontal and 2px
  vertical cause-label padding already used by Dart.
- `curated-wardley`: both renderers request bold axis labels; the remaining
  visual difference is in font measurement or rasterization rather than the
  diagram style constants.

## Reference limitations or acceptable differences

- `curated-math`: looks correct; Flutter is larger.
- `curated-architecture`: Flutter's rounded corners look preferable, while
  Mermaid.js uses hard corners.
- `curated-cynefin`: Mermaid.js does not render the source, so it cannot serve
  as a parity reference for this case.
- `curated-railroad`: Mermaid.js does not render the source, so the Dart output
  cannot be judged as parity against this reference case. Flutter's black text
  boxes remain a separate rendering defect.
