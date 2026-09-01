# Mermaid parity review findings — batch 01

Captured from the first Lavish feedback send. Mermaid.js is the reference and
the Flutter render is the review target unless noted otherwise.

## Confirmed differences

- `curated-subgraphs` (`packages/mermaid_samples:subgraphs`)
  - `Stage One` is too close to the top edge.
  - There is too little padding around the `Stage One` / `Stage Two` labels and
    between the lower boxes and the subgraph boundary.
- `curated-block` (`packages/mermaid_samples:block`)
  - Mermaid.js keeps both rows the same width.
  - The yellow group aligns with the left and right edges of the top row.
  - `Worker 1` and `Worker 2` expand to fill that row.
- `curated-kanban` (`packages/mermaid_samples:kanban`)
  - Mermaid.js uses more vivid colors.
- `curated-ishikawa` (`packages/mermaid_samples:ishikawa`)
  - `Technology` and `People` have insufficient padding.
  - Their text baseline is too low and touches the bottom edge.
- `curated-railroad` (`packages/mermaid_samples:railroad`)
  - Mermaid.js does not render this source.
  - Flutter shows black boxes where text should be rendered.
- `curated-radar` (`packages/mermaid_samples:radar`)
  - Mermaid.js uses slightly more vivid colors.
- `curated-treemap` (`packages/mermaid_samples:treemap`)
  - Flutter is taller.
  - Mermaid.js splits `API` and `DB` vertically; Flutter splits them
    horizontally.
- `curated-venn` (`packages/mermaid_samples:venn`)
  - Mermaid.js keeps all labels on the same baseline.
  - Flutter places `Frontend` and `Backend` near the tops of their circles.
- `curated-wardley` (`packages/mermaid_samples:wardley`)
  - Mermaid.js renders `Visibility` and `Evolution` in bold.
- `curated-handdrawn` (`packages/mermaid_samples:handdrawn`)
  - The edge from `Debug` to `Is it working?` is partially hidden behind the
    diamond.
- `upstream-c4-05`
  (`packages/mermaid_core/test/fixtures/upstream_c4/05.mmd`)
  - The second line of `Customer's mobile device` is obscured by the blue box.
  - Mermaid.js shows `[Container: Xamarin]` and does not separate the container
    label above `Mobile App` in the same way as Flutter.
  - Flutter uses dashed boundary borders where Mermaid.js uses solid borders.
- `upstream-class-11`
  (`packages/mermaid_core/test/fixtures/upstream_class/11.mmd`)
  - `Logo Shape` is faint or partially transparent in Flutter but solid in
    Mermaid.js.
  - Mermaid.js places `Car` inside the `Vehicles` box.
- `upstream-er-03`
  (`packages/mermaid_core/test/fixtures/upstream_er/03.mmd`)
  - Table-cell padding is too small; for example, `PK` touches the right edge.

## Reference limitations or acceptable differences

- `curated-math`: looks correct; Flutter is larger.
- `curated-architecture`: Flutter's rounded corners look preferable, while
  Mermaid.js uses hard corners.
- `curated-cynefin`: Mermaid.js does not render the source, so it cannot serve
  as a parity reference for this case.
