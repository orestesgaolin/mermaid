/// TextPainter-backed [core.TextMeasurer] plus the shared spec→TextStyle
/// mapping used by both measurement and painting (they must agree exactly,
/// otherwise layout and paint disagree about text block sizes).
library;

import 'package:flutter/painting.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;

/// CSS generic family keywords that have no direct Flutter equivalent; they
/// are skipped so the engine's default fallback chain applies.
const Set<String> _genericFamilies = {
  'sans-serif',
  'serif',
  'monospace',
  'cursive',
  'fantasy',
  'system-ui',
};

/// Parses a CSS font-family list (e.g. `"trebuchet ms", verdana, sans-serif`)
/// into a primary family and a fallback list. Quotes are stripped and generic
/// keywords are skipped.
({String? family, List<String> fallback}) parseCssFontFamily(String css) {
  final names = <String>[];
  for (final part in css.split(',')) {
    var name = part.trim();
    if (name.length >= 2 &&
        ((name.startsWith('"') && name.endsWith('"')) ||
            (name.startsWith("'") && name.endsWith("'")))) {
      name = name.substring(1, name.length - 1).trim();
    }
    if (name.isEmpty || _genericFamilies.contains(name.toLowerCase())) {
      continue;
    }
    names.add(name);
  }
  return (
    family: names.isEmpty ? null : names.first,
    fallback: names.length > 1 ? List.unmodifiable(names.sublist(1)) : const [],
  );
}

/// Maps a CSS numeric weight (100..900) to a [FontWeight].
FontWeight fontWeightFromCss(int weight) {
  final index = (weight ~/ 100).clamp(1, 9) - 1;
  return FontWeight.values[index];
}

/// Line-height factor shared by measurement and painting.
const double kMermaidTextHeightFactor = 1.2;

/// Builds the Flutter [TextStyle] for a [core.TextStyleSpec]. Both
/// [FlutterTextMeasurer] and the scene painter use this so measured and
/// painted text have identical metrics.
TextStyle textStyleFromSpec(core.TextStyleSpec spec, {Color? color}) {
  final families = parseCssFontFamily(spec.fontFamily);
  return TextStyle(
    color: color,
    fontFamily: families.family,
    fontFamilyFallback: families.fallback.isEmpty ? null : families.fallback,
    fontSize: spec.fontSize,
    fontWeight: fontWeightFromCss(spec.fontWeight),
    fontStyle: spec.italic ? FontStyle.italic : FontStyle.normal,
    height: kMermaidTextHeightFactor,
  );
}

/// Exact text measurement via [TextPainter], matching how `ScenePainter`
/// paints text (same style mapping, ltr, no text scaling).
class FlutterTextMeasurer implements core.TextMeasurer {
  const FlutterTextMeasurer();

  @override
  core.Size measure(String text, core.TextStyleSpec style, {double? maxWidth}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyleFromSpec(style)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    final size = core.Size(
      painter.size.width.ceilToDouble(),
      painter.size.height.ceilToDouble(),
    );
    painter.dispose();
    return size;
  }
}
