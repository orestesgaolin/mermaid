/// Icon support, mirroring upstream `registerIconPacks` + iconify usage.
///
/// An icon pack is an iconify-style set: a `prefix`, a default `width`/`height`
/// (the icon viewBox; iconify defaults to 24), and a map of icon name → SVG
/// `body` (the inner markup of the `<svg>`). Icons are referenced as
/// `"prefix:name"`, e.g. `"logos:aws"`.
///
/// We ship a tiny built-in pack so the feature works out of the box and is
/// verifiable; consumers can register more packs (e.g. a full `@iconify-json/*`
/// dump decoded to [IconPack]).
library;

import '../color.dart';
import '../geometry.dart';
import '../ir/scene.dart';
import 'svg_path.dart';

class IconDef {
  const IconDef(this.body, {this.width = 24, this.height = 24});

  /// Inner SVG markup, typically one or more `<path d="..."/>` elements.
  final String body;
  final double width;
  final double height;
}

class IconPack {
  const IconPack({required this.prefix, required this.icons});

  final String prefix;
  final Map<String, IconDef> icons;
}

final _packs = <String, IconPack>{};

/// Registers (or replaces) an icon pack. Mirrors `registerIconPacks`.
void registerIconPack(IconPack pack) => _packs[pack.prefix] = pack;

/// Looks up `"prefix:name"`; returns null if the pack or name is unknown.
IconDef? lookupIcon(String ref) {
  final i = ref.indexOf(':');
  if (i < 0) return null;
  final pack = _packs[ref.substring(0, i)];
  return pack?.icons[ref.substring(i + 1)];
}

/// Renders [ref]'s glyph as scene shapes scaled/centered into [box] (the icon
/// is fit preserving aspect ratio). Returns an empty list if unknown.
///
/// Each drawable SVG element (`<path>`, `<line>`, `<rect>`, `<circle>`,
/// `<ellipse>`) is honoured. When an element carries an inline `style` (or
/// `fill`/`stroke`/`stroke-width` attributes) those colors are used verbatim —
/// this is how the architecture pack draws white strokes on a coloured box.
/// Elements with no explicit paint default to a solid fill in [color], which
/// preserves the single-colour Material glyph behaviour used by other diagrams.
List<SceneNode> renderIcon(String ref, Rect box, Color color) {
  final def = lookupIcon(ref);
  if (def == null) return const [];
  final scale = (box.width / def.width).clamp(0.0, box.height / def.height);
  final dx = box.left + (box.width - def.width * scale) / 2;
  final dy = box.top + (box.height - def.height * scale) / 2;
  Point tf(Point p) => Point(dx + p.x * scale, dy + p.y * scale);

  final out = <SceneNode>[];
  for (final el in _svgElements(def.body)) {
    final geom = _geometryFor(el, tf, scale);
    if (geom == null) continue;
    final paint = _paintFor(el, color, scale);
    out.add(SceneShape(
        geometry: geom, fill: paint.$1, stroke: paint.$2));
  }
  return out;
}

/// A single drawable SVG element: its tag name and raw attribute string.
typedef _SvgElement = ({String tag, String attrs});

double? _attrNum(String attrs, String name) {
  final m = RegExp('\\s$name="([^"]*)"').firstMatch(attrs);
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

String? _styleProp(String attrs, String prop) {
  // Prefer an inline style declaration, then a standalone attribute.
  final style = RegExp(r'\sstyle="([^"]*)"').firstMatch(attrs)?.group(1);
  if (style != null) {
    final m = RegExp('(?:^|;)\\s*$prop\\s*:\\s*([^;]+)').firstMatch(style);
    if (m != null) return m.group(1)!.trim();
  }
  final attr = RegExp('\\s$prop="([^"]*)"').firstMatch(attrs)?.group(1);
  return attr?.trim();
}

/// Iterates the drawable elements of an SVG body fragment in document order.
Iterable<_SvgElement> _svgElements(String body) sync* {
  final re = RegExp(r'<(path|line|rect|circle|ellipse)\b([^>]*)>');
  for (final m in re.allMatches(body)) {
    yield (tag: m.group(1)!, attrs: m.group(2)!);
  }
}

ShapeGeometry? _geometryFor(
    _SvgElement el, Point Function(Point) tf, double scale) {
  switch (el.tag) {
    case 'path':
      final d = RegExp(r'\sd="([^"]*)"').firstMatch(el.attrs)?.group(1);
      final cmds = parseSvgPath(d).map((c) => _transform(c, tf)).toList();
      return cmds.isEmpty ? null : PathGeometry(cmds);
    case 'line':
      final x1 = _attrNum(el.attrs, 'x1') ?? 0;
      final y1 = _attrNum(el.attrs, 'y1') ?? 0;
      final x2 = _attrNum(el.attrs, 'x2') ?? 0;
      final y2 = _attrNum(el.attrs, 'y2') ?? 0;
      return PathGeometry([MoveTo(tf(Point(x1, y1))), LineTo(tf(Point(x2, y2)))]);
    case 'rect':
      final x = _attrNum(el.attrs, 'x') ?? 0;
      final y = _attrNum(el.attrs, 'y') ?? 0;
      final w = _attrNum(el.attrs, 'width') ?? 0;
      final h = _attrNum(el.attrs, 'height') ?? 0;
      final tl = tf(Point(x, y));
      final br = tf(Point(x + w, y + h));
      return RectGeometry(
        Rect.fromLTRB(tl.x, tl.y, br.x, br.y),
        rx: (_attrNum(el.attrs, 'rx') ?? 0) * scale,
        ry: (_attrNum(el.attrs, 'ry') ?? 0) * scale,
      );
    case 'circle':
      final c = tf(Point(_attrNum(el.attrs, 'cx') ?? 0, _attrNum(el.attrs, 'cy') ?? 0));
      return CircleGeometry(c, (_attrNum(el.attrs, 'r') ?? 0) * scale);
    case 'ellipse':
      final c = tf(Point(_attrNum(el.attrs, 'cx') ?? 0, _attrNum(el.attrs, 'cy') ?? 0));
      return EllipseGeometry(c, (_attrNum(el.attrs, 'rx') ?? 0) * scale,
          (_attrNum(el.attrs, 'ry') ?? 0) * scale);
  }
  return null;
}

/// Resolves the (fill, stroke) for an element. `none` disables a channel; an
/// element with no explicit paint falls back to a solid [fallback] fill.
(Fill?, Stroke?) _paintFor(_SvgElement el, Color fallback, double scale) {
  final fillStr = _styleProp(el.attrs, 'fill');
  final strokeStr = _styleProp(el.attrs, 'stroke');
  final hasAny = fillStr != null || strokeStr != null;

  Fill? fill;
  if (fillStr != null && fillStr != 'none') {
    fill = Fill(_parseColor(fillStr) ?? fallback);
  } else if (!hasAny) {
    fill = Fill(fallback);
  }

  Stroke? stroke;
  if (strokeStr != null && strokeStr != 'none') {
    final w = double.tryParse(
            (_styleProp(el.attrs, 'stroke-width') ?? '1').replaceAll('px', '')) ??
        1;
    stroke = Stroke(color: _parseColor(strokeStr) ?? fallback, width: w * scale);
  }
  return (fill, stroke);
}

Color? _parseColor(String s) {
  s = s.trim();
  if (s.startsWith('#')) {
    var hex = s.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(0xff000000 | v);
    }
    if (hex.length == 8) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(v);
    }
  }
  return switch (s.toLowerCase()) {
    'white' => Color.white,
    'black' => Color.black,
    _ => null,
  };
}

PathCommand _transform(PathCommand c, Point Function(Point) tf) => switch (c) {
      MoveTo(:final p) => MoveTo(tf(p)),
      LineTo(:final p) => LineTo(tf(p)),
      CubicTo(:final c1, :final c2, :final p) =>
        CubicTo(tf(c1), tf(c2), tf(p)),
      QuadTo(:final c, :final p) => QuadTo(tf(c), tf(p)),
      ClosePath() => const ClosePath(),
    };

/// A small built-in pack (prefix `icon`), registered on import so icons render
/// with no extra setup. Bodies are standard 24×24 Material-style path data.
/// Register fuller iconify packs with [registerIconPack] for more.
const _builtin = IconPack(prefix: 'icon', icons: {
  'cloud': IconDef(
      '<path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z"/>'),
  'database': IconDef(
      '<path d="M12 3C7.58 3 4 4.34 4 6v12c0 1.66 3.58 3 8 3s8-1.34 8-3V6c0-1.66-3.58-3-8-3zm0 2c3.87 0 6 1.07 6 1s-2.13 1-6 1-6-1.07-6-1 2.13-1 6-1zm6 11c0 .07-2.13 1-6 1s-6-.93-6-1v-2.23c1.61.78 3.72 1.23 6 1.23s4.39-.45 6-1.23V16zm0-4c0 .07-2.13 1-6 1s-6-.93-6-1V9.77C7.61 10.55 9.72 11 12 11s4.39-.45 6-1.23V12z"/>'),
  'star': IconDef(
      '<path d="M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/>'),
  'heart': IconDef(
      '<path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>'),
  'cog': IconDef(
      '<path d="M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zm0 6a2 2 0 1 1 0-4 2 2 0 0 1 0 4zm9-2 -2-.5c-.1-.5-.3-1-.5-1.4l1.1-1.7-1.4-1.4-1.7 1.1c-.4-.2-.9-.4-1.4-.5L13.5 3h-2L11 5.5c-.5.1-1 .3-1.4.5L7.9 4.9 6.5 6.3l1.1 1.7c-.2.4-.4.9-.5 1.4L4.5 10v2l2.6.6c.1.5.3 1 .5 1.4l-1.1 1.7 1.4 1.4 1.7-1.1c.4.2.9.4 1.4.5l.5 2.5h2l.6-2.5c.5-.1 1-.3 1.4-.5l1.7 1.1 1.4-1.4-1.1-1.7c.2-.4.4-.9.5-1.4L21 12z"/>'),
  // Architecture service icons (Material-style 24×24 paths).
  'server': IconDef(
      '<path d="M4 5h16a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zm2 2.5h2v1H6v-1zm12.5 0h1v1h-1v-1zM4 14h16a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1zm2 2.5h2v1H6v-1zm12.5 0h1v1h-1v-1z"/>'),
  'disk': IconDef(
      '<path d="M12 4c-4.42 0-8 1.34-8 3s3.58 3 8 3 8-1.34 8-3-3.58-3-8-3zm-8 5.5V14c0 1.66 3.58 3 8 3s8-1.34 8-3V9.5c0 1.66-3.58 3-8 3s-8-1.34-8-3z"/>'),
  'internet': IconDef(
      '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-2.95a15.7 15.7 0 0 0-1.38-3.56A8.03 8.03 0 0 1 18.9 8zM12 4c.83 1.2 1.48 2.53 1.91 4h-3.82c.43-1.47 1.08-2.8 1.91-4zM4.26 14a7.8 7.8 0 0 1 0-4h3.38a16.6 16.6 0 0 0 0 4H4.26zm.84 2h2.95c.32 1.25.78 2.45 1.38 3.56A7.99 7.99 0 0 1 5.1 16zm2.95-8H5.1a7.99 7.99 0 0 1 4.33-3.56A15.7 15.7 0 0 0 8.05 8zM12 20c-.83-1.2-1.48-2.53-1.91-4h3.82A13.7 13.7 0 0 1 12 20zm2.34-6H9.66a14.7 14.7 0 0 1 0-4h4.68a14.7 14.7 0 0 1 0 4zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95a8.03 8.03 0 0 1-4.33 3.56zM16.36 14a16.6 16.6 0 0 0 0-4h3.38a7.8 7.8 0 0 1 0 4h-3.38z"/>'),
});

/// The default architecture icon pack (upstream `mermaid-architecture`). Each
/// glyph is an 80×80 SVG: a solid `#087ebf` box overlaid with white-stroked
/// line art, ported verbatim from upstream `architectureIcons.ts` so service
/// nodes match mermaid.js pixel-for-pixel. Referenced as
/// `mermaid-architecture:<name>` (cloud/database/disk/internet/server/blank).
const _archIconBkg =
    '<rect width="80" height="80" style="fill: #087ebf; stroke-width: 0px;"/>';
const _architecture = IconPack(prefix: 'mermaid-architecture', icons: {
  'database': IconDef(
      '$_archIconBkg<path d="m20,57.86c0,3.94,8.95,7.14,20,7.14s20-3.2,20-7.14" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><path d="m20,45.95c0,3.94,8.95,7.14,20,7.14s20-3.2,20-7.14" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><path d="m20,34.05c0,3.94,8.95,7.14,20,7.14s20-3.2,20-7.14" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><ellipse cx="40" cy="22.14" rx="20" ry="7.14" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><line x1="20" y1="57.86" x2="20" y2="22.14" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><line x1="60" y1="57.86" x2="60" y2="22.14" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/>',
      width: 80,
      height: 80),
  'server': IconDef(
      '$_archIconBkg<rect x="17.5" y="17.5" width="45" height="45" rx="2" ry="2" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><line x1="17.5" y1="32.5" x2="62.5" y2="32.5" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><line x1="17.5" y1="47.5" x2="62.5" y2="47.5" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><path d="m56.25,25c0,.27-.45.5-1,.5h-10.5c-.55,0-1-.23-1-.5s.45-.5,1-.5h10.5c.55,0,1,.23,1,.5Z" style="fill: #fff; stroke-width: 0px;"/><path d="m56.25,40c0,.27-.45.5-1,.5h-10.5c-.55,0-1-.23-1-.5s.45-.5,1-.5h10.5c.55,0,1,.23,1,.5Z" style="fill: #fff; stroke-width: 0px;"/><path d="m56.25,55c0,.27-.45.5-1,.5h-10.5c-.55,0-1-.23-1-.5s.45-.5,1-.5h10.5c.55,0,1,.23,1,.5Z" style="fill: #fff; stroke-width: 0px;"/><circle cx="32.5" cy="25" r=".75" style="fill: #fff; stroke: #fff; stroke-miterlimit: 10;"/><circle cx="27.5" cy="25" r=".75" style="fill: #fff; stroke: #fff; stroke-miterlimit: 10;"/><circle cx="22.5" cy="25" r=".75" style="fill: #fff; stroke: #fff; stroke-miterlimit: 10;"/><circle cx="32.5" cy="40" r=".75" style="fill: #fff; stroke: #fff; stroke-miterlimit: 10;"/><circle cx="27.5" cy="40" r=".75" style="fill: #fff; stroke: #fff; stroke-miterlimit: 10;"/><circle cx="22.5" cy="40" r=".75" style="fill: #fff; stroke: #fff; stroke-miterlimit: 10;"/><circle cx="32.5" cy="55" r=".75" style="fill: #fff; stroke: #fff; stroke-miterlimit: 10;"/><circle cx="27.5" cy="55" r=".75" style="fill: #fff; stroke: #fff; stroke-miterlimit: 10;"/><circle cx="22.5" cy="55" r=".75" style="fill: #fff; stroke: #fff; stroke-miterlimit: 10;"/>',
      width: 80,
      height: 80),
  'disk': IconDef(
      '$_archIconBkg<rect x="20" y="15" width="40" height="50" rx="1" ry="1" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><ellipse cx="24" cy="19.17" rx=".8" ry=".83" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><ellipse cx="56" cy="19.17" rx=".8" ry=".83" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><ellipse cx="24" cy="60.83" rx=".8" ry=".83" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><ellipse cx="56" cy="60.83" rx=".8" ry=".83" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><ellipse cx="40" cy="33.75" rx="14" ry="14.58" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><ellipse cx="40" cy="33.75" rx="4" ry="4.17" style="fill: #fff; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><path d="m37.51,42.52l-4.83,13.22c-.26.71-1.1,1.02-1.76.64l-4.18-2.42c-.66-.38-.81-1.26-.33-1.84l9.01-10.8c.88-1.05,2.56-.08,2.09,1.2Z" style="fill: #fff; stroke-width: 0px;"/>',
      width: 80,
      height: 80),
  'internet': IconDef(
      '$_archIconBkg<circle cx="40" cy="40" r="22.5" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><line x1="40" y1="17.5" x2="40" y2="62.5" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><line x1="17.5" y1="40" x2="62.5" y2="40" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><path d="m39.99,17.51c-15.28,11.1-15.28,33.88,0,44.98" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><path d="m40.01,17.51c15.28,11.1,15.28,33.88,0,44.98" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><line x1="19.75" y1="30.1" x2="60.25" y2="30.1" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/><line x1="19.75" y1="49.9" x2="60.25" y2="49.9" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/>',
      width: 80,
      height: 80),
  'cloud': IconDef(
      '$_archIconBkg<path d="m65,47.5c0,2.76-2.24,5-5,5H20c-2.76,0-5-2.24-5-5,0-1.87,1.03-3.51,2.56-4.36-.04-.21-.06-.42-.06-.64,0-2.6,2.48-4.74,5.65-4.97,1.65-4.51,6.34-7.76,11.85-7.76.86,0,1.69.08,2.5.23,2.09-1.57,4.69-2.5,7.5-2.5,6.1,0,11.19,4.38,12.28,10.17,2.14.56,3.72,2.51,3.72,4.83,0,.03,0,.07-.01.1,2.29.46,4.01,2.48,4.01,4.9Z" style="fill: none; stroke: #fff; stroke-miterlimit: 10; stroke-width: 2px;"/>',
      width: 80,
      height: 80),
  'blank': IconDef(_archIconBkg, width: 80, height: 80),
});

bool _registered = false;

/// Ensures built-in packs are available. Idempotent; called by the renderer.
void ensureBuiltinIconPacks() {
  if (_registered) return;
  _registered = true;
  registerIconPack(_builtin);
  registerIconPack(_architecture);
}
