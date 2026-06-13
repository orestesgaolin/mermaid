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
/// is fit preserving aspect ratio). Returns an empty list if unknown. Each
/// `<path>` in the body is filled with [color].
List<SceneNode> renderIcon(String ref, Rect box, Color color) {
  final def = lookupIcon(ref);
  if (def == null) return const [];
  final scale = (box.width / def.width).clamp(0.0, box.height / def.height);
  final dx = box.left + (box.width - def.width * scale) / 2;
  final dy = box.top + (box.height - def.height * scale) / 2;
  Point tf(Point p) => Point(dx + p.x * scale, dy + p.y * scale);

  final out = <SceneNode>[];
  for (final d in _pathData(def.body)) {
    final cmds = parseSvgPath(d).map((c) => _transform(c, tf)).toList();
    if (cmds.isNotEmpty) {
      out.add(SceneShape(geometry: PathGeometry(cmds), fill: Fill(color)));
    }
  }
  return out;
}

/// Extracts the `d="..."` of every `<path>` in an SVG body fragment.
Iterable<String> _pathData(String body) =>
    RegExp(r'<path[^>]*\sd="([^"]*)"').allMatches(body).map((m) => m.group(1)!);

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
});

bool _registered = false;

/// Ensures built-in packs are available. Idempotent; called by the renderer.
void ensureBuiltinIconPacks() {
  if (_registered) return;
  _registered = true;
  registerIconPack(_builtin);
}
