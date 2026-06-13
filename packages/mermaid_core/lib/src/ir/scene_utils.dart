/// Shared geometry utilities over the scene IR: bounds computation and
/// rigid translation. Used by the per-diagram layout engines.
library;

import 'dart:math' as math;

import '../geometry.dart';
import 'scene.dart';

Rect? sceneBounds(Iterable<SceneNode> nodes) {
  Rect? acc;
  for (final n in nodes) {
    final b = sceneNodeBounds(n);
    if (b == null) continue;
    acc = acc == null ? b : acc.union(b);
  }
  return acc;
}

Rect? sceneNodeBounds(SceneNode node) => switch (node) {
      SceneGroup(:final children) => sceneBounds(children),
      SceneShape(:final geometry) => geometryBounds(geometry),
      SceneText(:final bounds, :final rotation) =>
        rotation == 0 ? bounds : _rotatedBounds(bounds, rotation),
    };

/// Axis-aligned bounding box of [r] rotated [deg] degrees about its center.
Rect _rotatedBounds(Rect r, double deg) {
  final rad = deg * math.pi / 180;
  final c = math.cos(rad).abs(), s = math.sin(rad).abs();
  final w = r.width * c + r.height * s;
  final h = r.width * s + r.height * c;
  return Rect.fromCenter(r.center, w, h);
}

Rect geometryBounds(ShapeGeometry g) => switch (g) {
      RectGeometry(:final rect) => rect,
      CircleGeometry(:final center, :final radius) =>
        Rect.fromCenter(center, radius * 2, radius * 2),
      EllipseGeometry(:final center, :final rx, :final ry) =>
        Rect.fromCenter(center, rx * 2, ry * 2),
      PolygonGeometry(:final points) => pointsBounds(points),
      PathGeometry(:final commands) => pointsBounds([
          for (final c in commands) ...pathCommandPoints(c),
        ]),
    };

List<Point> pathCommandPoints(PathCommand c) => switch (c) {
      MoveTo(:final p) => [p],
      LineTo(:final p) => [p],
      QuadTo(:final c, :final p) => [c, p],
      CubicTo(:final c1, :final c2, :final p) => [c1, c2, p],
      ClosePath() => const [],
    };

Rect pointsBounds(List<Point> pts) {
  if (pts.isEmpty) return const Rect.fromLTWH(0, 0, 0, 0);
  var minX = pts.first.x, maxX = pts.first.x;
  var minY = pts.first.y, maxY = pts.first.y;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

SceneNode translateSceneNode(SceneNode node, double dx, double dy) =>
    switch (node) {
      SceneGroup(:final id, :final semanticLabel, :final children) =>
        SceneGroup(
          id: id,
          semanticLabel: semanticLabel,
          children: [for (final c in children) translateSceneNode(c, dx, dy)],
        ),
      SceneShape(:final geometry, :final fill, :final stroke) => SceneShape(
          geometry: translateGeometry(geometry, dx, dy),
          fill: _translateFill(fill, dx, dy),
          stroke: stroke,
        ),
      SceneText(
        :final text,
        :final bounds,
        :final style,
        :final color,
        :final align
      ) =>
        SceneText(
          text: text,
          bounds: bounds.translate(dx, dy),
          style: style,
          color: color,
          align: align,
          rotation: node.rotation,
        ),
    };

/// Translates a fill's gradient coordinates (a solid fill is returned as-is).
Fill? _translateFill(Fill? fill, double dx, double dy) {
  final g = fill?.gradient;
  if (fill == null || g == null) return fill;
  return Fill(
    fill.color,
    gradient: SceneGradient(
      Point(g.from.x + dx, g.from.y + dy),
      Point(g.to.x + dx, g.to.y + dy),
      g.colors,
    ),
  );
}

ShapeGeometry translateGeometry(ShapeGeometry g, double dx, double dy) {
  Point t(Point p) => Point(p.x + dx, p.y + dy);
  return switch (g) {
    RectGeometry(:final rect, :final rx, :final ry) =>
      RectGeometry(rect.translate(dx, dy), rx: rx, ry: ry),
    CircleGeometry(:final center, :final radius) =>
      CircleGeometry(t(center), radius),
    EllipseGeometry(:final center, :final rx, :final ry) =>
      EllipseGeometry(t(center), rx, ry),
    PolygonGeometry(:final points) =>
      PolygonGeometry([for (final p in points) t(p)]),
    PathGeometry(:final commands) => PathGeometry([
        for (final c in commands)
          switch (c) {
            MoveTo(:final p) => MoveTo(t(p)),
            LineTo(:final p) => LineTo(t(p)),
            QuadTo(:final c, :final p) => QuadTo(t(c), t(p)),
            CubicTo(:final c1, :final c2, :final p) =>
              CubicTo(t(c1), t(c2), t(p)),
            ClosePath() => const ClosePath(),
          },
      ]),
  };
}
