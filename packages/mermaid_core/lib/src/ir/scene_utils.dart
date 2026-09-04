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

/// Caches [RenderSceneBounds.nodeBounds] per scene instance.
///
/// [RenderScene] is immutable, so the map is valid for the scene's lifetime.
/// Interaction layers call `boundsOfNode` from build and hover callbacks; a
/// fresh tree walk plus an unmodifiable map on every frame is wasted work.
final Expando<Map<String, Rect>> _nodeBoundsCache = Expando<Map<String, Rect>>(
  'RenderScene.nodeBounds',
);

Map<String, Rect> _computeNodeBounds(RenderScene scene) {
  final result = <String, Rect>{};

  void walk(Iterable<SceneNode> nodes) {
    for (final node in nodes) {
      if (node is! SceneGroup) continue;
      final id = node.id;
      if (id != null && node.role == SceneGroupRole.node) {
        final bounds = sceneBounds(node.children);
        if (bounds != null) result[id] = bounds;
      }
      walk(node.children);
    }
  }

  walk(scene.nodes);
  return Map.unmodifiable(result);
}

extension RenderSceneBounds on RenderScene {
  /// Bounds of non-empty diagram-node groups, keyed by stable node id.
  ///
  /// Coordinates are in scene space: x increases right, y increases down, and
  /// no Flutter viewport transformation has been applied. Bounds use the same
  /// [sceneBounds] calculation as interaction hit testing.
  ///
  /// Nested nodes are reported independently. If an id occurs more than once,
  /// the last-painted occurrence wins. Empty groups and groups whose role is
  /// not [SceneGroupRole.node] are omitted.
  ///
  /// The result is computed once per scene and cached, so repeated lookups
  /// from a paint or hover callback are cheap. The returned map is
  /// unmodifiable and shared between callers — do not hold it past the
  /// scene's own lifetime.
  Map<String, Rect> get nodeBounds =>
      _nodeBoundsCache[this] ??= _computeNodeBounds(this);

  /// Scene-space bounds for the node [id], or null when no non-empty node has
  /// that id.
  Rect? boundsOfNode(String id) => nodeBounds[id];
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
  CircleGeometry(:final center, :final radius) => Rect.fromCenter(
    center,
    radius * 2,
    radius * 2,
  ),
  EllipseGeometry(:final center, :final rx, :final ry) => Rect.fromCenter(
    center,
    rx * 2,
    ry * 2,
  ),
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
      SceneGroup(
        :final id,
        :final role,
        :final semanticLabel,
        :final link,
        :final tooltip,
        :final edge,
        :final children,
      ) =>
        SceneGroup(
          id: id,
          role: role,
          semanticLabel: semanticLabel,
          link: link,
          tooltip: tooltip,
          edge: edge,
          children: [for (final c in children) translateSceneNode(c, dx, dy)],
        ),
      SceneShape(
        :final geometry,
        :final fill,
        :final stroke,
        :final blendMode,
        :final paintRole,
      ) =>
        SceneShape(
          geometry: translateGeometry(geometry, dx, dy),
          fill: _translateFill(fill, dx, dy),
          stroke: _translateStroke(stroke, dx, dy),
          blendMode: blendMode,
          paintRole: paintRole,
        ),
      SceneText(
        :final text,
        :final bounds,
        :final style,
        :final color,
        :final align,
        :final underline,
        :final paintRole,
      ) =>
        SceneText(
          text: text,
          bounds: bounds.translate(dx, dy),
          style: style,
          color: color,
          align: align,
          rotation: node.rotation,
          underline: underline,
          paintRole: paintRole,
        ),
    };

/// Shortest scene-space distance from [point] to the painted path centreline.
///
/// Lines are measured exactly. Quadratic and cubic curves are adaptively
/// flattened until their control points are within [flatness] of the chord.
/// Returns positive infinity when the path contains no drawable segment.
double distanceToPath(PathGeometry path, Point point, {double flatness = 0.5}) {
  if (!flatness.isFinite || flatness <= 0) {
    throw ArgumentError.value(flatness, 'flatness', 'must be finite and > 0');
  }
  var distance = double.infinity;
  Point? current;
  Point? subpathStart;

  void segment(Point a, Point b) {
    distance = math.min(distance, _distanceToSegment(point, a, b));
  }

  void quadratic(Point p0, Point c, Point p1, int depth) {
    if (depth >= 12 || _distanceToSegment(c, p0, p1) <= flatness) {
      segment(p0, p1);
      return;
    }
    final p01 = _midpoint(p0, c);
    final p12 = _midpoint(c, p1);
    final mid = _midpoint(p01, p12);
    quadratic(p0, p01, mid, depth + 1);
    quadratic(mid, p12, p1, depth + 1);
  }

  void cubic(Point p0, Point c1, Point c2, Point p1, int depth) {
    final flat = math.max(
      _distanceToSegment(c1, p0, p1),
      _distanceToSegment(c2, p0, p1),
    );
    if (depth >= 12 || flat <= flatness) {
      segment(p0, p1);
      return;
    }
    final p01 = _midpoint(p0, c1);
    final p12 = _midpoint(c1, c2);
    final p23 = _midpoint(c2, p1);
    final p012 = _midpoint(p01, p12);
    final p123 = _midpoint(p12, p23);
    final mid = _midpoint(p012, p123);
    cubic(p0, p01, p012, mid, depth + 1);
    cubic(mid, p123, p23, p1, depth + 1);
  }

  for (final command in path.commands) {
    switch (command) {
      case MoveTo(:final p):
        current = p;
        subpathStart = p;
      case LineTo(:final p):
        if (current != null) segment(current, p);
        current = p;
      case QuadTo(:final c, :final p):
        if (current != null) quadratic(current, c, p, 0);
        current = p;
      case CubicTo(:final c1, :final c2, :final p):
        if (current != null) cubic(current, c1, c2, p, 0);
        current = p;
      case ClosePath():
        if (current != null && subpathStart != null) {
          segment(current, subpathStart);
          current = subpathStart;
        }
    }
  }
  return distance;
}

Point _midpoint(Point a, Point b) => Point((a.x + b.x) / 2, (a.y + b.y) / 2);

double _distanceToSegment(Point p, Point a, Point b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) {
    return math.sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y));
  }
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared).clamp(
    0.0,
    1.0,
  );
  final x = a.x + t * dx;
  final y = a.y + t * dy;
  return math.sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y));
}

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

/// Translates a stroke's gradient coordinates (a solid stroke is unchanged).
Stroke? _translateStroke(Stroke? stroke, double dx, double dy) {
  final g = stroke?.gradient;
  if (stroke == null || g == null) return stroke;
  return Stroke(
    color: stroke.color,
    width: stroke.width,
    dash: stroke.dash,
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
    RectGeometry(:final rect, :final rx, :final ry) => RectGeometry(
      rect.translate(dx, dy),
      rx: rx,
      ry: ry,
    ),
    CircleGeometry(:final center, :final radius) => CircleGeometry(
      t(center),
      radius,
    ),
    EllipseGeometry(:final center, :final rx, :final ry) => EllipseGeometry(
      t(center),
      rx,
      ry,
    ),
    PolygonGeometry(:final points) => PolygonGeometry([
      for (final p in points) t(p),
    ]),
    PathGeometry(:final commands) => PathGeometry([
      for (final c in commands)
        switch (c) {
          MoveTo(:final p) => MoveTo(t(p)),
          LineTo(:final p) => LineTo(t(p)),
          QuadTo(:final c, :final p) => QuadTo(t(c), t(p)),
          CubicTo(:final c1, :final c2, :final p) => CubicTo(
            t(c1),
            t(c2),
            t(p),
          ),
          ClosePath() => const ClosePath(),
        },
    ]),
  };
}
