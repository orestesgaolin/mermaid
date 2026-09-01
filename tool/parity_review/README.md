# Mermaid parity review

This local tool generates a stacked visual review of complex Mermaid fixtures:

- Mermaid.js reference SVG
- native Flutter PNG rendered with `FlutterTextMeasurer` and `ScenePainter`
- optional `mermaid_core` SVG rendered with approximate text metrics

From the workspace root, generate the first batch and build the report:

```sh
fvm flutter test apps/demo/test/parity_review_test.dart -r expanded
fvm dart run tool/parity_review/build_report.dart
lavish-axi build/parity_review/index.html
```

The report embeds the generated Flutter PNGs and core SVGs. If captured
Mermaid.js SVGs are absent, it renders them live using the same Mermaid.js 11
CDN module as the comparison website. The generated `capture.html` is a small
capture surface for making those references fully offline later.

The first batch contains the largest upstream fixture in each checked-in
diagram family plus complex curated samples for the newer diagram types.
