/// Text measurement abstraction.
///
/// Layout depends on text dimensions, so every rendering backend must provide
/// a [TextMeasurer]. The Flutter backend wraps TextPainter (exact); the
/// pure-Dart fallback in [approximate_text_measurer.dart] uses per-character
/// advance tables (approximate, good enough for tests and server-side SVG).
library;

import '../geometry.dart';
import 'text_style.dart';

abstract interface class TextMeasurer {
  /// Measures [text], which may contain `\n` for explicit line breaks.
  ///
  /// If [maxWidth] is given, lines longer than it are soft-wrapped at word
  /// boundaries (matching what the paint backend will do) and the returned
  /// size reflects the wrapped block.
  Size measure(String text, TextStyleSpec style, {double? maxWidth});
}
