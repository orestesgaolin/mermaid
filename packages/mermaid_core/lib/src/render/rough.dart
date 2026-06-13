/// Hand-drawn ("rough") rendering, mirroring upstream's `look: 'handDrawn'`
/// (which uses roughjs). This is a deterministic scene → scene transform:
/// every filled/stroked [SceneShape] is replaced by a group of sketchy
/// double-stroked outlines plus hachure (parallel diagonal) fill lines,
/// seeded by `handDrawnSeed` so the output is stable. [SceneText] is left
/// untouched.
///
/// Defaults match upstream `userNodeOverrides`: roughness 0.7, fillStyle
/// hachure, fillWeight 4, hachureGap 5.2, strokeWidth 1.3, hachure −41°.
library;

import 'dart:math' as math;

import '../geometry.dart';
import '../ir/scene.dart';

/// Returns a copy of [scene] rendered in the hand-drawn style.
RenderScene roughenScene(RenderScene scene, {int seed = 0}) {
  final rng = _Rng(seed);
  return RenderScene(
    size: scene.size,
    background: scene.background,
    nodes: [for (final n in scene.nodes) _roughenNode(n, rng)],
  );
}

SceneNode _roughenNode(SceneNode node, _Rng rng) {
  switch (node) {
    case SceneGroup(:final children, :final id, :final semanticLabel):
      return SceneGroup(
        id: id,
        semanticLabel: semanticLabel,
        children: [for (final c in children) _roughenNode(c, rng)],
      );
    case SceneText():
      return node;
    case SceneShape():
      return SceneGroup(children: _roughenShape(node, rng));
  }
}

const _hachureGap = 5.2;
const _fillWeight = 4.0;
const _hachureAngle = -41 * math.pi / 180;

List<SceneNode> _roughenShape(SceneShape shape, _Rng rng) {
  final out = <SceneNode>[];
  final closed = _isClosed(shape.geometry);
  final outline = _outlinePoints(shape.geometry);

  // Hachure fill lines first (they sit under the sketchy outline).
  if (shape.fill != null && closed && outline.length >= 3) {
    final lines = _hachure(outline, _hachureGap);
    for (final (a, b) in lines) {
      out.add(SceneShape(
        geometry: PathGeometry(_roughLine(a, b, rng, 1.0)),
        stroke: Stroke(color: shape.fill!.color, width: _fillWeight * 0.6),
      ));
    }
  }

  // Sketchy outline: two passes for the doubled hand-drawn stroke. Use the
  // stroke color if present, else the fill color so filled-only shapes still
  // get a sketched border like upstream.
  final strokeColor = shape.stroke?.color ?? shape.fill?.color;
  if (strokeColor != null) {
    final width = shape.stroke?.width ?? 1.3;
    final segments = _segments(shape.geometry);
    for (var pass = 0; pass < 2; pass++) {
      final cmds = <PathCommand>[];
      for (final (a, b) in segments) {
        cmds.addAll(_roughLine(a, b, rng, 2.6));
      }
      out.add(SceneShape(
        geometry: PathGeometry(cmds),
        stroke: Stroke(color: strokeColor, width: width, dash: shape.stroke?.dash),
      ));
    }
  }

  return out;
}

bool _isClosed(ShapeGeometry g) => switch (g) {
      RectGeometry() => true,
      CircleGeometry() => true,
      EllipseGeometry() => true,
      PolygonGeometry() => true,
      PathGeometry() => false,
    };

/// Outline as a single polygon point ring (for hachure clipping).
List<Point> _outlinePoints(ShapeGeometry g) => switch (g) {
      RectGeometry(:final rect) => [
          Point(rect.left, rect.top),
          Point(rect.right, rect.top),
          Point(rect.right, rect.bottom),
          Point(rect.left, rect.bottom),
        ],
      CircleGeometry(:final center, :final radius) =>
        _ellipsePoints(center, radius, radius),
      EllipseGeometry(:final center, :final rx, :final ry) =>
        _ellipsePoints(center, rx, ry),
      PolygonGeometry(:final points) => points,
      PathGeometry() => const [],
    };

/// Edge segments (a→b pairs) to sketch as the outline.
List<(Point, Point)> _segments(ShapeGeometry g) {
  switch (g) {
    case RectGeometry() ||
          CircleGeometry() ||
          EllipseGeometry() ||
          PolygonGeometry():
      final pts = _outlinePoints(g);
      return [
        for (var i = 0; i < pts.length; i++) (pts[i], pts[(i + 1) % pts.length])
      ];
    case PathGeometry(:final commands):
      final segs = <(Point, Point)>[];
      Point? cur;
      Point? start;
      for (final c in commands) {
        switch (c) {
          case MoveTo(:final p):
            cur = p;
            start = p;
          case LineTo(:final p):
            if (cur != null) segs.add((cur, p));
            cur = p;
          case CubicTo(:final c1, :final c2, :final p):
            if (cur != null) {
              // Flatten the bezier into a few segments.
              var prev = cur;
              const steps = 6;
              for (var i = 1; i <= steps; i++) {
                final t = i / steps;
                final pt = _cubic(cur, c1, c2, p, t);
                segs.add((prev, pt));
                prev = pt;
              }
            }
            cur = p;
          case QuadTo(:final c, :final p):
            if (cur != null) {
              var prev = cur;
              const steps = 5;
              for (var i = 1; i <= steps; i++) {
                final t = i / steps;
                final pt = _quad(cur, c, p, t);
                segs.add((prev, pt));
                prev = pt;
              }
            }
            cur = p;
          case ClosePath():
            if (cur != null && start != null) segs.add((cur, start));
            cur = start;
        }
      }
      return segs;
  }
}

Point _cubic(Point p0, Point p1, Point p2, Point p3, double t) {
  final u = 1 - t;
  final a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
  return Point(
    a * p0.x + b * p1.x + c * p2.x + d * p3.x,
    a * p0.y + b * p1.y + c * p2.y + d * p3.y,
  );
}

Point _quad(Point p0, Point p1, Point p2, double t) {
  final u = 1 - t;
  return Point(
    u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
    u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y,
  );
}

List<Point> _ellipsePoints(Point c, double rx, double ry) {
  const n = 18;
  return [
    for (var i = 0; i < n; i++)
      Point(
        c.x + rx * math.cos(2 * math.pi * i / n),
        c.y + ry * math.sin(2 * math.pi * i / n),
      ),
  ];
}

/// One sketchy stroke from [a] to [b] as a wobbly cubic. [maxOff] caps the
/// perturbation amount in px (outlines wobble more than fill lines).
List<PathCommand> _roughLine(Point a, Point b, _Rng rng, double maxOff) {
  final len = _dist(a, b);
  final off = math.min(maxOff, len / 6) + 0.5;
  double j() => (rng.next() * 2 - 1) * off;
  // Control points at ~1/3 and ~2/3 with random offsets, plus jittered ends.
  final start = Point(a.x + j() * 0.5, a.y + j() * 0.5);
  final end = Point(b.x + j() * 0.5, b.y + j() * 0.5);
  final c1 = Point(a.x + (b.x - a.x) / 3 + j(), a.y + (b.y - a.y) / 3 + j());
  final c2 =
      Point(a.x + 2 * (b.x - a.x) / 3 + j(), a.y + 2 * (b.y - a.y) / 3 + j());
  return [MoveTo(start), CubicTo(c1, c2, end)];
}

/// Hachure fill: parallel lines at [_hachureAngle] spaced [gap], clipped to
/// the (convex) polygon via a rotated scanline sweep.
List<(Point, Point)> _hachure(List<Point> poly, double gap) {
  final cos = math.cos(-_hachureAngle), sin = math.sin(-_hachureAngle);
  // Rotate polygon into hachure-aligned space.
  Point rot(Point p) => Point(p.x * cos - p.y * sin, p.x * sin + p.y * cos);
  Point unrot(Point p) =>
      Point(p.x * cos + p.y * sin, -p.x * sin + p.y * cos);
  final rp = poly.map(rot).toList();
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in rp) {
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final out = <(Point, Point)>[];
  for (var y = minY + gap; y < maxY; y += gap) {
    final xs = <double>[];
    for (var i = 0; i < rp.length; i++) {
      final p1 = rp[i], p2 = rp[(i + 1) % rp.length];
      final lo = math.min(p1.y, p2.y), hi = math.max(p1.y, p2.y);
      if (y < lo || y >= hi) continue;
      final t = (y - p1.y) / (p2.y - p1.y);
      xs.add(p1.x + t * (p2.x - p1.x));
    }
    xs.sort();
    for (var i = 0; i + 1 < xs.length; i += 2) {
      out.add((unrot(Point(xs[i], y)), unrot(Point(xs[i + 1], y))));
    }
  }
  return out;
}

double _dist(Point a, Point b) =>
    math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

/// Tiny deterministic LCG so a given seed always produces the same sketch.
class _Rng {
  _Rng(int seed) : _state = (seed * 2654435761 + 0x9e3779b9) & 0x7fffffff;
  int _state;

  /// Uniform double in [0, 1).
  double next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}
