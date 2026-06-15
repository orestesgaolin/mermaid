/// Lays out TeX math using the pure-Dart `katex` package and adapts its
/// backend-agnostic box tree into mermaid's scene IR.
///
/// `katex` is a faithful KaTeX port (verified against the real KaTeX oracle).
/// It produces a [BoxNode] tree in em units; here we walk that tree — exactly
/// as katex's own SVG serializer does — but emit mermaid [SceneShape]/
/// [SceneText] primitives instead of SVG. Glyphs are emitted as filled outline
/// **paths** (from katex's bundled glyph outlines), so math renders in both the
/// SVG and Flutter backends with no font embedding or registration required.
library;

import 'dart:math' as math;

import 'package:katex/katex.dart' as kx;

import '../color.dart';
import '../geometry.dart';
import '../icons/svg_path.dart';
import '../ir/scene.dart';

/// A laid-out math result relative to a top-left origin of (0,0): the [size],
/// the [ascent] (top→baseline distance) and the absolute scene [nodes].
typedef KatexMath = ({Size size, double ascent, List<SceneNode> nodes});

/// Padding (em) around the metric box so glyph ink that overshoots isn't
/// clipped (mirrors katex's serializer `_contentPadEm`).
const double _padEm = 0.08;

/// Lays out [tex] at [fontSize] px-per-em in [color]. Returns null if katex
/// can't parse/build it (the caller falls back to its own engine).
KatexMath? buildKatexMath(String tex, double fontSize, Color color) {
  final kx.BoxNode root;
  try {
    root = kx.renderToBox(tex);
  } catch (_) {
    // Parse/build error (or unsupported construct) — let the caller fall back.
    return null;
  }

  final pad = _padEm * fontSize;
  final ascent = pad + root.height * fontSize;
  final out = <SceneNode>[];
  try {
    _emit(root, pad, ascent, fontSize, color, out);
  } catch (_) {
    return null;
  }
  final size = Size(
    root.width * fontSize + 2 * pad,
    (root.height + root.depth) * fontSize + 2 * pad,
  );
  return (size: size, ascent: ascent, nodes: out);
}

/// Emits [node] with its left edge at [penX] and baseline at [baselineY]
/// (top-left origin, y growing downward; one em = [scale] px).
void _emit(kx.BoxNode node, double penX, double baselineY, double scale,
    Color color, List<SceneNode> out) {
  switch (node) {
    case kx.GlyphNode():
      _emitGlyph(node, penX, baselineY, scale, color, out);
    case kx.RuleNode():
      _emitRule(node, penX, baselineY, scale, color, out);
    case kx.KernNode():
      break; // pure advance, handled by the parent row
    case kx.HBox():
      _emitRow(node.children, penX, baselineY, scale, color, out);
    case kx.SpanNode():
      final c = node.color != null ? (Color.tryParse(node.color!) ?? color) : color;
      _emitRow(node.children, penX, baselineY, scale, c, out);
    case kx.VList():
      for (final pos in node.positions) {
        // shift = downward offset of the child baseline from the vlist baseline.
        _emit(pos.box, penX, baselineY + pos.shift * scale, scale, color, out);
      }
    case kx.SvgPathNode():
      _emitSvgPath(node, penX, baselineY, scale, color, out);
    case kx.EncloseNode():
      // Decorations (frames/strikes) are niche; render the inner content.
      _emit(node.child, penX, baselineY, scale, color, out);
    case kx.ImageNode():
      break; // \includegraphics — not supported in diagram labels
  }
}

void _emitRow(List<kx.BoxNode> children, double penX, double baselineY,
    double scale, Color color, List<SceneNode> out) {
  var x = penX;
  for (final child in children) {
    if (child is! kx.KernNode) {
      _emit(child, x, baselineY, scale, color, out);
    }
    x += child.width * scale;
  }
}

void _emitGlyph(kx.GlyphNode node, double penX, double baselineY, double scale,
    Color color, List<SceneNode> out) {
  final path = kx.katexGlyphPaths[node.font.fontName]?[node.codepoint];
  if (path == null) return; // missing outline — skip (rare)
  // Outlines are in font units (y-up); scale by size/unitsPerEm and flip Y so
  // the glyph baseline lands on baselineY.
  final s = (scale * node.size) / kx.katexGlyphUnitsPerEm;
  final cmds = _mapPath(
    parseSvgPath(path),
    (p) => Point(penX + p.x * s, baselineY - p.y * s),
  );
  if (cmds.isEmpty) return;
  out.add(SceneShape(geometry: PathGeometry(cmds), fill: Fill(color)));
}

void _emitRule(kx.RuleNode node, double penX, double baselineY, double scale,
    Color color, List<SceneNode> out) {
  final rect = Rect.fromLTWH(
    penX,
    baselineY - node.height * scale,
    node.width * scale,
    (node.height + node.depth) * scale,
  );
  out.add(SceneShape(geometry: RectGeometry(rect), fill: Fill(color)));
}

void _emitSvgPath(kx.SvgPathNode node, double penX, double baselineY,
    double scale, Color color, List<SceneNode> out) {
  if (node.pathData.isEmpty || node.viewBoxWidth <= 0 || node.viewBoxHeight <= 0) {
    return;
  }
  final boxW = node.width * scale;
  final boxH = (node.height + node.depth) * scale;
  final top = baselineY - node.height * scale;
  final cmds = parseSvgPath(node.pathData);
  if (cmds.isEmpty) return;

  final Point Function(Point) m;
  if (node.preserveAspectRatio == kx.SvgPreserveAspectRatio.none) {
    // Non-uniform stretch to fill the box exactly (stacked delimiters).
    final sx = boxW / node.viewBoxWidth;
    final sy = boxH / node.viewBoxHeight;
    m = (p) => Point(penX + p.x * sx, top + p.y * sy);
  } else {
    // "slice": uniform scale to *cover* the box, anchored per the variant,
    // overflow clipped — emulated by clamping points to the box (exact for the
    // surd vinculum and arrow shafts, which run off-box horizontally).
    final s =
        math.max(boxW / node.viewBoxWidth, boxH / node.viewBoxHeight);
    final scaledW = node.viewBoxWidth * s;
    final offX = switch (node.preserveAspectRatio) {
      kx.SvgPreserveAspectRatio.xMaxYMinSlice => boxW - scaledW,
      kx.SvgPreserveAspectRatio.xMidYMinSlice => (boxW - scaledW) / 2,
      _ => 0.0, // xMinYMin (and none, unreachable here)
    };
    m = (p) => Point(
          (penX + offX + p.x * s).clamp(penX, penX + boxW),
          (top + p.y * s).clamp(top, top + boxH),
        );
  }
  out.add(SceneShape(geometry: PathGeometry(_mapPath(cmds, m)), fill: Fill(color)));
}

/// Maps every point of [cmds] through [m] (used to bake a glyph/path transform
/// into absolute scene coordinates).
List<PathCommand> _mapPath(List<PathCommand> cmds, Point Function(Point) m) => [
      for (final c in cmds)
        switch (c) {
          MoveTo() => MoveTo(m(c.p)),
          LineTo() => LineTo(m(c.p)),
          CubicTo() => CubicTo(m(c.c1), m(c.c2), m(c.p)),
          QuadTo() => QuadTo(m(c.c), m(c.p)),
          ClosePath() => const ClosePath(),
        }
    ];
