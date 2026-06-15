import 'package:jaspr/dom.dart';

/// The site accent — purple, the mermaid dart brand colour. (The sibling katex
/// comparison site shares this layout but uses a blue accent.)
const primaryColor = Color('#4a3a8a');

// Base document styling (font + reset) lives in `main.server.dart` so it sits
// in the shared `<head>` alongside the Inter import; component-level styles are
// defined next to each component via `@css`. This global rule-set is kept (and
// referenced by the generated server options) but intentionally empty.
@css
List<StyleRule> get styles => [];
