## 0.1.0

Initial release.

- `MermaidDiagram` widget: parses, lays out and paints any `mermaid_core`
  diagram natively (no SVG/WebView).
- `FlutterTextMeasurer` (TextPainter-based) and `ScenePainter` (CustomPainter)
  for lower-level use.
- Live-editing support: keeps the last good render with an error overlay.
- Theme argument plus `%%{init}%%`/frontmatter overrides.
