/// Geometry helpers shared by the record-style diagram layouts (class, state,
/// ER, requirement, C4).
///
/// These layouts all place rectangular nodes, route edges between them and
/// label the routes, so they need the same handful of primitives: clip a
/// segment to a node border, smooth a dagre polyline, find the middle of a
/// route. Each used to carry a private copy; they live here instead.
///
/// Flowchart keeps its own copies on purpose — its versions are tuned to the
/// flowchart renderer and are covered by separate parity tests.
library;

import 'dart:math' as math;

import 'geometry.dart';
import 'ir/scene.dart';

/// The point on [rect]'s border along the line from its centre to [outside].
///
/// Mirrors dagre-d3's `intersectRect`: picks the side the ray leaves through,
/// so an edge stops on the border instead of running to the centre.
Point intersectRect(Rect rect, Point outside) {
  final c = rect.center;
  final dx = outside.x - c.x;
  final dy = outside.y - c.y;
  if (dx == 0 && dy == 0) return c;
  final w = rect.width / 2;
  final h = rect.height / 2;
  double sx, sy;
  if (dy.abs() * w > dx.abs() * h) {
    sy = dy < 0 ? -h : h;
    sx = dx * sy / dy;
  } else {
    sx = dx < 0 ? -w : w;
    sy = dy * sx / dx;
  }
  return Point(c.x + sx, c.y + sy);
}

/// One cubic segment of a uniform B-spline through `p0`, `p1`, `p`.
///
/// Matches d3-shape's `curveBasis` point emission.
CubicTo basisSegment(Point p0, Point p1, Point p) => CubicTo(
  Point((2 * p0.x + p1.x) / 3, (2 * p0.y + p1.y) / 3),
  Point((p0.x + 2 * p1.x) / 3, (p0.y + 2 * p1.y) / 3),
  Point((p0.x + 4 * p1.x + p.x) / 6, (p0.y + 4 * p1.y + p.y) / 6),
);

/// Smooths [pts] with d3's `curveBasis`, the curve upstream uses for edges.
///
/// Fewer than three points cannot form a spline, so they pass through as a
/// move/line pair.
List<PathCommand> curveBasis(List<Point> pts) {
  if (pts.isEmpty) return const [];
  if (pts.length == 1) return [MoveTo(pts.first)];
  if (pts.length == 2) return [MoveTo(pts[0]), LineTo(pts[1])];
  final cmds = <PathCommand>[
    MoveTo(pts[0]),
    LineTo(Point((5 * pts[0].x + pts[1].x) / 6, (5 * pts[0].y + pts[1].y) / 6)),
  ];
  for (var i = 2; i < pts.length; i++) {
    cmds.add(basisSegment(pts[i - 2], pts[i - 1], pts[i]));
  }
  final n = pts.length;
  cmds.add(basisSegment(pts[n - 2], pts[n - 1], pts[n - 1]));
  cmds.add(LineTo(pts[n - 1]));
  return cmds;
}

/// The point halfway along [points] by arc length (not by index).
///
/// Used to centre an edge label on the visible middle of a route.
Point polylineMidpoint(List<Point> points) {
  if (points.isEmpty) return Point.zero;
  if (points.length == 1) return points.first;
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += points[i].distanceTo(points[i - 1]);
  }
  var remaining = total / 2;
  for (var i = 1; i < points.length; i++) {
    final length = points[i].distanceTo(points[i - 1]);
    if (length >= remaining) {
      final fraction = length == 0 ? 0.0 : remaining / length;
      return Point(
        points[i - 1].x + (points[i].x - points[i - 1].x) * fraction,
        points[i - 1].y + (points[i].y - points[i - 1].y) * fraction,
      );
    }
    remaining -= length;
  }
  return points.last;
}

/// Flattens [path] into a polyline, splitting each cubic into [cubicSteps]
/// straight pieces. Quadratics and closes are ignored — no layout here emits
/// them on an edge route.
List<Point> samplePath(PathGeometry path, {int cubicSteps = 16}) {
  final samples = <Point>[];
  Point? current;
  for (final command in path.commands) {
    switch (command) {
      case MoveTo(:final p):
        current = p;
        samples.add(p);
      case LineTo(:final p):
        current = p;
        samples.add(p);
      case CubicTo(:final c1, :final c2, :final p):
        final start = current;
        if (start == null) break;
        for (var step = 1; step <= cubicSteps; step++) {
          final t = step / cubicSteps;
          final u = 1 - t;
          samples.add(
            Point(
              u * u * u * start.x +
                  3 * u * u * t * c1.x +
                  3 * u * t * t * c2.x +
                  t * t * t * p.x,
              u * u * u * start.y +
                  3 * u * u * t * c1.y +
                  3 * u * t * t * c2.y +
                  t * t * t * p.y,
            ),
          );
        }
        current = p;
      case QuadTo():
      case ClosePath():
        break;
    }
  }
  return samples;
}

/// Arc-length midpoint of [path], sampled finely enough for label placement.
Point pathMidpoint(PathGeometry path) => polylineMidpoint(samplePath(path));

/// Unit vector along `v`. A zero vector has no direction, so it reports
/// straight down — the fallback every caller wants for a degenerate edge.
Point normalize(Point v) {
  final len = math.sqrt(v.x * v.x + v.y * v.y);
  return len == 0 ? const Point(0, 1) : Point(v.x / len, v.y / len);
}

/// Unit vector pointing from [from] to [to].
Point direction(Point from, Point to) => normalize(to - from);

/// True when [a] and [b] share area. Touching borders do not count.
bool rectsOverlap(Rect a, Rect b) =>
    a.left < b.right &&
    a.right > b.left &&
    a.top < b.bottom &&
    a.bottom > b.top;

/// True when [inner] lies wholly within [outer] (shared borders allowed).
bool rectContainsRect(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.right <= outer.right &&
    inner.top >= outer.top &&
    inner.bottom <= outer.bottom;

/// Strips one layer of matched surrounding quotes from [text].
///
/// Whitespace around the token is trimmed first, so `  "A"  ` yields `A`. Set
/// [singleQuotes] to false where `'` is ordinary text (C4 and git labels).
String unquote(String text, {bool singleQuotes = true}) {
  final s = text.trim();
  if (s.length >= 2 &&
      ((s.startsWith('"') && s.endsWith('"')) ||
          (singleQuotes && s.startsWith("'") && s.endsWith("'")))) {
    return s.substring(1, s.length - 1);
  }
  return s;
}
