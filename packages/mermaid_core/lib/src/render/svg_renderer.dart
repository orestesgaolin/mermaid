/// SVG string backend: serializes a [RenderScene] to standalone SVG.
///
/// Pure serialization — every layout/styling decision was already made when
/// the scene was built, so this stays trivially in sync with the Flutter
/// painter. Soft-wrapped text is emitted per explicit `\n` line (the
/// measurer's soft wrap points are not part of the IR yet).
library;

import '../color.dart';
import '../ir/scene.dart';
import '../math/katex_fonts.dart';
import '../text/text_style.dart';

String renderSceneToSvg(RenderScene scene) {
  final b = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg" ')
    ..write('width="${_num(scene.size.width)}" ')
    ..write('height="${_num(scene.size.height)}" ')
    ..write(
        'viewBox="0 0 ${_num(scene.size.width)} ${_num(scene.size.height)}">');
  // Self-contained KaTeX math fonts: embed @font-face only when used.
  if (_usesKatex(scene.nodes)) {
    b
      ..write('<defs><style>')
      ..write('@font-face{font-family:"KaTeX_Main";src:url(data:font/ttf;'
          'base64,$katexMainRegularTtfBase64) format("truetype");}')
      ..write('@font-face{font-family:"KaTeX_Math";src:url(data:font/ttf;'
          'base64,$katexMathItalicTtfBase64) format("truetype");}')
      ..write('</style></defs>');
  }
  final bg = scene.background;
  if (bg != null && bg.alpha > 0) {
    b.write('<rect width="100%" height="100%" fill="${_color(bg)}"/>');
  }
  final ids = _IdGen();
  for (final node in scene.nodes) {
    _writeNode(b, node, ids);
  }
  b.write('</svg>');
  return b.toString();
}

class _IdGen {
  int _n = 0;
  String next() => 'g${_n++}';
}

void _writeNode(StringBuffer b, SceneNode node, _IdGen ids) {
  switch (node) {
    case SceneGroup(:final id, :final semanticLabel, :final children):
      b.write('<g');
      if (id != null) b.write(' id="${_escapeAttr(id)}"');
      if (semanticLabel != null) {
        b.write(' aria-label="${_escapeAttr(semanticLabel)}"');
      }
      b.write('>');
      for (final c in children) {
        _writeNode(b, c, ids);
      }
      b.write('</g>');

    case SceneShape(:final geometry, :final fill, :final stroke):
      final paint = StringBuffer();
      final gradient = fill?.gradient;
      if (gradient != null) {
        final gid = ids.next();
        b
          ..write('<linearGradient id="$gid" gradientUnits="userSpaceOnUse" ')
          ..write('x1="${_num(gradient.from.x)}" y1="${_num(gradient.from.y)}" ')
          ..write('x2="${_num(gradient.to.x)}" y2="${_num(gradient.to.y)}">');
        for (var i = 0; i < gradient.colors.length; i++) {
          final c = gradient.colors[i];
          final off = gradient.colors.length == 1
              ? 0.0
              : i / (gradient.colors.length - 1);
          b.write('<stop offset="${_num(off)}" stop-color="${_color(c)}"');
          if (c.alpha < 255) b.write(' stop-opacity="${_num(c.alpha / 255)}"');
          b.write('/>');
        }
        b.write('</linearGradient>');
        paint.write(' fill="url(#$gid)"');
      } else {
        paint.write(' fill="${fill != null ? _color(fill.color) : 'none'}"');
        if (fill != null && fill.color.alpha < 255 && fill.color.alpha > 0) {
          paint.write(' fill-opacity="${_num(fill.color.alpha / 255)}"');
        }
      }
      if (stroke != null) {
        paint
          ..write(' stroke="${_color(stroke.color)}"')
          ..write(' stroke-width="${_num(stroke.width)}"');
        if (stroke.color.alpha < 255 && stroke.color.alpha > 0) {
          paint.write(' stroke-opacity="${_num(stroke.color.alpha / 255)}"');
        }
        final dash = stroke.dash;
        if (dash != null && dash.isNotEmpty) {
          paint.write(
              ' stroke-dasharray="${dash.map(_num).join(',')}"');
        }
      }
      switch (geometry) {
        case RectGeometry(:final rect, :final rx):
          b.write('<rect x="${_num(rect.left)}" y="${_num(rect.top)}" '
              'width="${_num(rect.width)}" height="${_num(rect.height)}"');
          if (rx > 0) b.write(' rx="${_num(rx)}"');
          b.write('$paint/>');
        case CircleGeometry(:final center, :final radius):
          b.write('<circle cx="${_num(center.x)}" cy="${_num(center.y)}" '
              'r="${_num(radius)}"$paint/>');
        case EllipseGeometry(:final center, :final rx, :final ry):
          b.write('<ellipse cx="${_num(center.x)}" cy="${_num(center.y)}" '
              'rx="${_num(rx)}" ry="${_num(ry)}"$paint/>');
        case PolygonGeometry(:final points):
          b.write('<polygon points="');
          b.write(points.map((p) => '${_num(p.x)},${_num(p.y)}').join(' '));
          b.write('"$paint/>');
        case PathGeometry(:final commands):
          b.write('<path d="');
          for (final c in commands) {
            switch (c) {
              case MoveTo(:final p):
                b.write('M${_num(p.x)} ${_num(p.y)}');
              case LineTo(:final p):
                b.write('L${_num(p.x)} ${_num(p.y)}');
              case QuadTo(:final c, :final p):
                b.write('Q${_num(c.x)} ${_num(c.y)} ${_num(p.x)} ${_num(p.y)}');
              case CubicTo(:final c1, :final c2, :final p):
                b.write('C${_num(c1.x)} ${_num(c1.y)} '
                    '${_num(c2.x)} ${_num(c2.y)} ${_num(p.x)} ${_num(p.y)}');
              case ClosePath():
                b.write('Z');
            }
          }
          b.write('"$paint/>');
      }

    case SceneText(
        :final text,
        :final bounds,
        :final style,
        :final color,
        :final align,
        :final rotation
      ):
      final lines = text.split('\n');
      final lineHeight = bounds.height / lines.length;
      final (anchor, x) = switch (align) {
        TextAlignH.left => ('start', bounds.left),
        TextAlignH.center => ('middle', bounds.center.x),
        TextAlignH.right => ('end', bounds.right),
      };
      if (rotation != 0) {
        b.write('<g transform="rotate(${_num(rotation)} '
            '${_num(bounds.center.x)} ${_num(bounds.center.y)})">');
      }
      b
        ..write('<text text-anchor="$anchor" ')
        ..write('font-family="${_escapeAttr(_svgFontFamily(style))}" ')
        ..write('font-size="${_num(style.fontSize)}"');
      if (style.fontWeight != 400) {
        b.write(' font-weight="${style.fontWeight}"');
      }
      if (style.italic) b.write(' font-style="italic"');
      b.write(' fill="${_color(color)}">');
      for (var i = 0; i < lines.length; i++) {
        final y = bounds.top + lineHeight * i + lineHeight * 0.78;
        b
          ..write('<tspan x="${_num(x)}" y="${_num(y)}">')
          ..write(_escapeText(lines[i]))
          ..write('</tspan>');
      }
      b.write('</text>');
      if (rotation != 0) b.write('</g>');
  }
}

String _svgFontFamily(TextStyleSpec style) => style.fontFamily;

/// True if any text node uses a KaTeX math font (so we embed the @font-face).
bool _usesKatex(List<SceneNode> nodes) => nodes.any((n) => switch (n) {
      SceneGroup(:final children) => _usesKatex(children),
      SceneText(:final style) => style.fontFamily.startsWith('KaTeX_'),
      _ => false,
    });

String _num(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
      RegExp(r'\.$'), '');
}

String _color(Color c) {
  final rgb = c.value & 0xffffff;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

String _escapeText(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeAttr(String s) =>
    _escapeText(s).replaceAll('"', '&quot;').replaceAll('\n', ' ');
