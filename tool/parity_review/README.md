# Mermaid parity review

This local tool generates a stacked visual review of complex Mermaid fixtures:

- Mermaid.js reference SVG
- native Flutter PNG rendered with `FlutterTextMeasurer` and `ScenePainter`
- optional `mermaid_core` SVG rendered with approximate text metrics

From the workspace root, generate the corpus and build the report:

```sh
fvm flutter test apps/demo/tool/parity_review_test.dart -r expanded
fvm dart run tool/parity_review/build_report.dart
lavish-axi build/parity_review/index.html
```

The corpus generator lives in `apps/demo/tool/` rather than `apps/demo/test/`
so a plain `flutter test` does not rebuild it; the corresponding cheap check
that every case still renders is `apps/demo/test/render_corpus_smoke_test.dart`.
The generator is macOS only and fails fast if the system fonts it rasterizes
with are missing. Both it and `build_report.dart` pin Mermaid.js `11.17.2`.

The last step is optional: `lavish-axi` is the operator's local review viewer,
which supplies the `window.lavish.queuePrompt` bridge behind each case's
"queue finding" button. Without it, open `build/parity_review/index.html` in
any browser — everything renders normally and the submit button just prints
"Open this report in Lavish to queue the finding" instead of queueing it, so
findings have to be written up by hand.

The report embeds the generated Flutter PNGs and core SVGs. If captured
Mermaid.js SVGs are absent, it renders them live using the same pinned
Mermaid.js CDN module as the comparison website. The generated `capture.html`
is a small capture surface for making those references fully offline later.

The batch contains the largest upstream fixture in each checked-in diagram
family plus complex curated samples for the newer diagram types; the shared
list lives in `apps/demo/test/support/parity_corpus.dart`.
