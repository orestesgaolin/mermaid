/// Hand-drawn ("rough") rendering — a faithful port of roughjs (the library
/// upstream uses for `look: 'handDrawn'`), not an approximation. The
/// algorithm, constants and PRNG mirror rough-stuff/rough `src/renderer.ts`,
/// `src/math.ts` and the `hachure-fill` scanline; the option values mirror
/// mermaid's `userNodeOverrides` (roughness 0.7, fillStyle hachure,
/// fillWeight 4, hachureGap 5.2, strokeWidth 1.3, hachureAngle −41).
///
/// This is a deterministic scene → scene transform: every filled/stroked
/// [SceneShape] is re-drawn as sketchy stroke paths; [SceneText] is left
/// untouched. Each shape's PRNG is reset to `seed` so identical shapes get
/// identical sketches, exactly like mermaid passing one `handDrawnSeed` to
/// every node.
library;

import 'dart:math' as math;

import '../geometry.dart';
import '../ir/scene.dart';

/// Returns a copy of [scene] rendered in the hand-drawn style. [seed] is the
/// `handDrawnSeed`; 0 means "random" upstream, but we substitute a fixed seed
/// so the output is stable (useful for the website and golden tests).
RenderScene roughenScene(RenderScene scene, {int seed = 0}) {
  final s = seed == 0 ? 1 : seed;
  return RenderScene(
    size: scene.size,
    background: scene.background,
    nodes: [for (final n in scene.nodes) _roughenNode(n, s)],
  );
}

SceneNode _roughenNode(SceneNode node, int seed) {
  switch (node) {
    case SceneGroup(:final children, :final id, :final semanticLabel):
      // Math expressions stay crisp — sketching glyph outlines is illegible.
      if (id == mathSceneGroupId) return node;
      return SceneGroup(
        id: id,
        semanticLabel: semanticLabel,
        children: [for (final c in children) _roughenNode(c, seed)],
      );
    case SceneText():
      return node;
    case SceneShape():
      return SceneGroup(children: _roughenShape(node, seed));
  }
}

// ---------------------------------------------------------------------------
// roughjs option set (mermaid handDrawn overrides + rough defaults).
// ---------------------------------------------------------------------------

class _Opts {
  _Opts(int seed) : randomizer = _Random(seed), _seed = seed;

  final double maxRandomnessOffset = 2;
  final double roughness = 0.7; // mermaid override (rough default 1)
  final double bowing = 1;
  final double curveTightness = 0;
  final double curveFitting = 0.95;
  final int curveStepCount = 9;
  final double fillWeight = 4; // mermaid override
  final double hachureAngle = -41;
  final double hachureGap = 5.2; // mermaid override
  final bool disableMultiStroke = false;

  final int _seed;
  _Random randomizer;

  /// rough's `cloneOptionsAlterSeed`: a fresh randomizer seeded seed+1.
  _Opts alterSeed() => _Opts(_seed == 0 ? 0 : _seed + 1);
}

double _random(_Opts o) => o.randomizer.next();

double _offset(double min, double max, _Opts o, [double gain = 1]) =>
    o.roughness * gain * ((_random(o) * (max - min)) + min);

double _offsetOpt(double x, _Opts o, [double gain = 1]) =>
    _offset(-x, x, o, gain);

// ---------------------------------------------------------------------------
// Park–Miller PRNG, exactly as rough's `Random` (Math.imul / 2^31).
// ---------------------------------------------------------------------------

class _Random {
  _Random(this._seed);
  int _seed;

  double next() {
    // seed = Math.imul(48271, seed); return ((2^31-1) & seed) / 2^31
    _seed = _imul(48271, _seed);
    return (_seed & 0x7fffffff) / 2147483648.0;
  }

  static int _imul(int a, int b) => (a * b).toSigned(32);
}

// ---------------------------------------------------------------------------
// rough op stream → our PathCommand list.
// ---------------------------------------------------------------------------

sealed class _Op {
  const _Op();
}

class _Move extends _Op {
  const _Move(this.x, this.y);
  final double x, y;
}

class _Bcurve extends _Op {
  const _Bcurve(this.c1x, this.c1y, this.c2x, this.c2y, this.x, this.y);
  final double c1x, c1y, c2x, c2y, x, y;
}

class _Line extends _Op {
  const _Line(this.x, this.y);
  final double x, y;
}

List<PathCommand> _toCommands(List<_Op> ops) => [
      for (final op in ops)
        switch (op) {
          _Move(:final x, :final y) => MoveTo(Point(x, y)),
          _Bcurve(:final c1x, :final c1y, :final c2x, :final c2y, :final x, :final y) =>
            CubicTo(Point(c1x, c1y), Point(c2x, c2y), Point(x, y)),
          _Line(:final x, :final y) => LineTo(Point(x, y)),
        }
    ];

// ---------------------------------------------------------------------------
// rough renderer port: _line / doubleLine / linearPath / curve / ellipse.
// ---------------------------------------------------------------------------

List<_Op> _lineOps(
    double x1, double y1, double x2, double y2, _Opts o, bool move, bool overlay) {
  final lengthSq = math.pow(x1 - x2, 2) + math.pow(y1 - y2, 2);
  final length = math.sqrt(lengthSq);
  double gain;
  if (length < 200) {
    gain = 1;
  } else if (length > 500) {
    gain = 0.4;
  } else {
    gain = -0.0016668 * length + 1.233334;
  }

  var offset = o.maxRandomnessOffset;
  if (offset * offset * 100 > lengthSq) offset = length / 10;
  final halfOffset = offset / 2;
  final divergePoint = 0.2 + _random(o) * 0.2;
  var midDispX = o.bowing * o.maxRandomnessOffset * (y2 - y1) / 200;
  var midDispY = o.bowing * o.maxRandomnessOffset * (x1 - x2) / 200;
  midDispX = _offsetOpt(midDispX, o, gain);
  midDispY = _offsetOpt(midDispY, o, gain);

  final ops = <_Op>[];
  double randHalf() => _offsetOpt(halfOffset, o, gain);
  double randFull() => _offsetOpt(offset, o, gain);

  if (move) {
    if (overlay) {
      ops.add(_Move(x1 + randHalf(), y1 + randHalf()));
    } else {
      ops.add(_Move(x1 + randFull(), y1 + randFull()));
    }
  }
  if (overlay) {
    ops.add(_Bcurve(
      midDispX + x1 + (x2 - x1) * divergePoint + randHalf(),
      midDispY + y1 + (y2 - y1) * divergePoint + randHalf(),
      midDispX + x1 + 2 * (x2 - x1) * divergePoint + randHalf(),
      midDispY + y1 + 2 * (y2 - y1) * divergePoint + randHalf(),
      x2 + randHalf(),
      y2 + randHalf(),
    ));
  } else {
    ops.add(_Bcurve(
      midDispX + x1 + (x2 - x1) * divergePoint + randFull(),
      midDispY + y1 + (y2 - y1) * divergePoint + randFull(),
      midDispX + x1 + 2 * (x2 - x1) * divergePoint + randFull(),
      midDispY + y1 + 2 * (y2 - y1) * divergePoint + randFull(),
      x2 + randFull(),
      y2 + randFull(),
    ));
  }
  return ops;
}

List<_Op> _doubleLine(double x1, double y1, double x2, double y2, _Opts o) {
  final o1 = _lineOps(x1, y1, x2, y2, o, true, false);
  if (o.disableMultiStroke) return o1;
  return [...o1, ..._lineOps(x1, y1, x2, y2, o, true, true)];
}

List<_Op> _linearPath(List<Point> pts, bool close, _Opts o) {
  final len = pts.length;
  if (len > 2) {
    final ops = <_Op>[];
    for (var i = 0; i < len - 1; i++) {
      ops.addAll(_doubleLine(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, o));
    }
    if (close) {
      ops.addAll(_doubleLine(pts[len - 1].x, pts[len - 1].y, pts[0].x, pts[0].y, o));
    }
    return ops;
  } else if (len == 2) {
    return _doubleLine(pts[0].x, pts[0].y, pts[1].x, pts[1].y, o);
  }
  return [];
}

List<_Op> _curve(List<Point> points, _Opts o) {
  final len = points.length;
  final ops = <_Op>[];
  if (len > 3) {
    final s = 1 - o.curveTightness;
    ops.add(_Move(points[1].x, points[1].y));
    for (var i = 1; i + 2 < len; i++) {
      final v = points[i];
      final b1 = Point(
        v.x + (s * points[i + 1].x - s * points[i - 1].x) / 6,
        v.y + (s * points[i + 1].y - s * points[i - 1].y) / 6,
      );
      final b2 = Point(
        points[i + 1].x + (s * points[i].x - s * points[i + 2].x) / 6,
        points[i + 1].y + (s * points[i].y - s * points[i + 2].y) / 6,
      );
      ops.add(_Bcurve(b1.x, b1.y, b2.x, b2.y, points[i + 1].x, points[i + 1].y));
    }
  } else if (len == 3) {
    ops.add(_Move(points[1].x, points[1].y));
    ops.add(_Bcurve(points[1].x, points[1].y, points[2].x, points[2].y,
        points[2].x, points[2].y));
  } else if (len == 2) {
    ops.addAll(_lineOps(points[0].x, points[0].y, points[1].x, points[1].y, o, true, true));
  }
  return ops;
}


({double increment, double rx, double ry}) _ellipseParams(
    double width, double height, _Opts o) {
  final psq = math.sqrt(
      math.pi * 2 * math.sqrt((math.pow(width / 2, 2) + math.pow(height / 2, 2)) / 2));
  final stepCount =
      math.max(o.curveStepCount, o.curveStepCount / math.sqrt(200) * psq).ceil();
  final increment = math.pi * 2 / stepCount;
  var rx = (width / 2).abs();
  var ry = (height / 2).abs();
  final fit = 1 - o.curveFitting;
  rx += _offsetOpt(rx * fit, o);
  ry += _offsetOpt(ry * fit, o);
  return (increment: increment, rx: rx, ry: ry);
}

List<Point> _computeEllipsePoints(double increment, double cx, double cy,
    double rx, double ry, double offset, double overlap, _Opts o) {
  final all = <Point>[];
  final radOffset = _offsetOpt(0.5, o) - math.pi / 2;
  all.add(Point(
    _offsetOpt(offset, o) + cx + 0.9 * rx * math.cos(radOffset - increment),
    _offsetOpt(offset, o) + cy + 0.9 * ry * math.sin(radOffset - increment),
  ));
  final endAngle = math.pi * 2 + radOffset - 0.01;
  for (var angle = radOffset; angle < endAngle; angle += increment) {
    all.add(Point(
      _offsetOpt(offset, o) + cx + rx * math.cos(angle),
      _offsetOpt(offset, o) + cy + ry * math.sin(angle),
    ));
  }
  all.add(Point(
    _offsetOpt(offset, o) + cx + rx * math.cos(radOffset + math.pi * 2 + overlap * 0.5),
    _offsetOpt(offset, o) + cy + ry * math.sin(radOffset + math.pi * 2 + overlap * 0.5),
  ));
  all.add(Point(
    _offsetOpt(offset, o) + cx + 0.98 * rx * math.cos(radOffset + overlap),
    _offsetOpt(offset, o) + cy + 0.98 * ry * math.sin(radOffset + overlap),
  ));
  all.add(Point(
    _offsetOpt(offset, o) + cx + 0.9 * rx * math.cos(radOffset + overlap * 0.5),
    _offsetOpt(offset, o) + cy + 0.9 * ry * math.sin(radOffset + overlap * 0.5),
  ));
  return all;
}

List<_Op> _ellipse(double cx, double cy, double width, double height, _Opts o) {
  final p = _ellipseParams(width, height, o);
  final ap1 = _computeEllipsePoints(p.increment, cx, cy, p.rx, p.ry, 1,
      p.increment * _offset(0.1, _offset(0.4, 1, o), o), o);
  var o1 = _curve(ap1, o);
  if (!o.disableMultiStroke) {
    final ap2 = _computeEllipsePoints(p.increment, cx, cy, p.rx, p.ry, 1.5, 0, o);
    o1 = [...o1, ..._curve(ap2, o)];
  }
  return o1;
}

// ---------------------------------------------------------------------------
// hachure fill: rotate → scanline (hachure-fill port) → rotate back.
// ---------------------------------------------------------------------------

List<(Point, Point)> _hachureLines(
    List<Point> polygon, double gapIn, double angle, int skipOffset) {
  final gap = math.max(gapIn, 0.1);
  final center = const Point(0, 0);
  // Rotate into hachure-aligned space (angle in degrees).
  List<Point> rotate(List<Point> pts, double deg) {
    final f = math.pi / 180 * deg;
    final c = math.cos(f), s = math.sin(f);
    return [
      for (final p in pts)
        Point((p.x - center.x) * c - (p.y - center.y) * s + center.x,
            (p.x - center.x) * s + (p.y - center.y) * c + center.y)
    ];
  }

  final rp = rotate(polygon, angle);

  // Ensure closed.
  final poly = [...rp];
  if (poly.first.x != poly.last.x || poly.first.y != poly.last.y) {
    poly.add(poly.first);
  }
  if (poly.length <= 2) return [];

  // Edge table.
  final edges = <({double ymin, double ymax, double x, double islope})>[];
  for (var i = 0; i < poly.length - 1; i++) {
    final p1 = poly[i], p2 = poly[i + 1];
    if (p1.y != p2.y) {
      final ymin = math.min(p1.y, p2.y);
      edges.add((
        ymin: ymin,
        ymax: math.max(p1.y, p2.y),
        x: ymin == p1.y ? p1.x : p2.x,
        islope: (p2.x - p1.x) / (p2.y - p1.y),
      ));
    }
  }
  edges.sort((a, b) {
    if (a.ymin != b.ymin) return a.ymin < b.ymin ? -1 : 1;
    if (a.x != b.x) return a.x < b.x ? -1 : 1;
    return a.ymax == b.ymax ? 0 : (a.ymax < b.ymax ? -1 : 1);
  });
  if (edges.isEmpty) return [];

  final lines = <(Point, Point)>[];
  var active = <({double s, ({double ymin, double ymax, double x, double islope}) edge})>[];
  // Mutable x for active edges (edge.x advances each scan step).
  final ax = <int, double>{};
  var y = edges.first.ymin;
  var c = 0;
  final remaining = [...edges];
  while (active.isNotEmpty || remaining.isNotEmpty) {
    if (remaining.isNotEmpty) {
      var t = -1;
      for (var i = 0; i < remaining.length && !(remaining[i].ymin > y); i++) {
        t = i;
      }
      final added = remaining.sublist(0, t + 1);
      remaining.removeRange(0, t + 1);
      for (final e in added) {
        active.add((s: y, edge: e));
        ax[identityHashCode(e)] = e.x;
      }
    }
    active = active.where((a) => !(a.edge.ymax <= y)).toList();
    active.sort((a, b) {
      final xa = ax[identityHashCode(a.edge)]!, xb = ax[identityHashCode(b.edge)]!;
      return xa == xb ? 0 : (xa < xb ? -1 : 1);
    });
    // Scan steps by `gap`; `skipOffset` (only > 1 when roughness ≥ 1) thins
    // the lines by drawing every skipOffset-th row.
    if ((skipOffset <= 1 || c % skipOffset == 0) && active.length > 1) {
      for (var i = 0; i + 1 < active.length; i += 2) {
        final x1 = ax[identityHashCode(active[i].edge)]!;
        final x2 = ax[identityHashCode(active[i + 1].edge)]!;
        lines.add((Point(x1.roundToDouble(), y), Point(x2.roundToDouble(), y)));
      }
    }
    y += gap;
    for (final a in active) {
      ax[identityHashCode(a.edge)] =
          ax[identityHashCode(a.edge)]! + gap * a.edge.islope;
    }
    c++;
  }
  // Rotate lines back.
  final out = <(Point, Point)>[];
  for (final l in lines) {
    final r = rotate([l.$1, l.$2], -angle);
    out.add((r[0], r[1]));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Shape → rough op streams.
// ---------------------------------------------------------------------------

List<SceneNode> _roughenShape(SceneShape shape, int seed) {
  final out = <SceneNode>[];
  final isEllipse = shape.geometry is CircleGeometry || shape.geometry is EllipseGeometry;
  // A closed PathGeometry (pie wedge, radar area) encloses a fillable region;
  // flatten it to a polygon outline so hachure clipping has a ring to work on.
  final geom = shape.geometry;
  final isClosedPath =
      geom is PathGeometry && shape.fill != null && _pathIsClosed(geom);
  final outline =
      isClosedPath ? _flattenPath(geom) : _outlinePoints(shape.geometry);
  final closed = isClosedPath || _isClosed(shape.geometry);

  // Hachure fill under the outline.
  if (shape.fill != null && closed && outline.length >= 3) {
    final o = _Opts(seed);
    // hachureAngle + 90, exactly as polygonHachureLines.
    var skip = 1;
    if (o.roughness >= 1 && o.randomizer.next() > 0.7) skip = o.hachureGap.round();
    final lines = _hachureLines(outline, o.hachureGap, o.hachureAngle + 90, skip);
    final ops = <_Op>[];
    for (final (a, b) in lines) {
      ops.addAll(_doubleLine(a.x, a.y, b.x, b.y, o));
    }
    if (ops.isNotEmpty) {
      out.add(SceneShape(
        geometry: PathGeometry(_toCommands(ops)),
        stroke: Stroke(color: shape.fill!.color, width: o.fillWeight * 0.5),
      ));
    }
  }

  // Sketchy outline.
  final strokeColor = shape.stroke?.color ?? shape.fill?.color;
  if (strokeColor != null) {
    final o = _Opts(seed);
    final width = shape.stroke?.width ?? 1.3;
    List<_Op> ops;
    if (isEllipse) {
      final (cx, cy, w, h) = _ellipseBox(shape.geometry);
      ops = _ellipse(cx, cy, w, h, o);
    } else if (shape.geometry is PathGeometry) {
      ops = _roughPath(shape.geometry as PathGeometry, o);
    } else {
      ops = _linearPath(outline, true, o);
    }
    out.add(SceneShape(
      geometry: PathGeometry(_toCommands(ops)),
      stroke: Stroke(color: strokeColor, width: width, dash: shape.stroke?.dash),
    ));
  }

  return out;
}

/// Roughen an open path (e.g. a flowchart edge): flatten beziers to points,
/// then sketch the polyline with doubled lines.
List<_Op> _roughPath(PathGeometry g, _Opts o) {
  final ops = <_Op>[];
  final pts = <Point>[];
  Point? cur;
  void flush() {
    if (pts.length >= 2) ops.addAll(_linearPath(pts, false, o));
    pts.clear();
  }

  for (final c in g.commands) {
    switch (c) {
      case MoveTo(:final p):
        flush();
        cur = p;
        pts.add(p);
      case LineTo(:final p):
        pts.add(p);
        cur = p;
      case CubicTo(:final c1, :final c2, :final p):
        if (cur != null) {
          const steps = 8;
          for (var i = 1; i <= steps; i++) {
            pts.add(_cubic(cur, c1, c2, p, i / steps));
          }
        }
        cur = p;
      case QuadTo(:final c, :final p):
        if (cur != null) {
          const steps = 6;
          for (var i = 1; i <= steps; i++) {
            pts.add(_quad(cur, c, p, i / steps));
          }
        }
        cur = p;
      case ClosePath():
        flush();
    }
  }
  flush();
  return ops;
}

bool _isClosed(ShapeGeometry g) => switch (g) {
      RectGeometry() => true,
      CircleGeometry() => true,
      EllipseGeometry() => true,
      PolygonGeometry() => true,
      PathGeometry() => false,
    };

List<Point> _outlinePoints(ShapeGeometry g) => switch (g) {
      RectGeometry(:final rect) => [
          Point(rect.left, rect.top),
          Point(rect.right, rect.top),
          Point(rect.right, rect.bottom),
          Point(rect.left, rect.bottom),
        ],
      CircleGeometry(:final center, :final radius) =>
        _polyEllipse(center, radius, radius),
      EllipseGeometry(:final center, :final rx, :final ry) =>
        _polyEllipse(center, rx, ry),
      PolygonGeometry(:final points) => points,
      PathGeometry() => const [],
    };

(double, double, double, double) _ellipseBox(ShapeGeometry g) => switch (g) {
      CircleGeometry(:final center, :final radius) =>
        (center.x, center.y, radius * 2, radius * 2),
      EllipseGeometry(:final center, :final rx, :final ry) =>
        (center.x, center.y, rx * 2, ry * 2),
      _ => (0, 0, 0, 0),
    };

/// A polygon ring approximating an ellipse, used only for hachure clipping.
List<Point> _polyEllipse(Point c, double rx, double ry) {
  const n = 24;
  return [
    for (var i = 0; i < n; i++)
      Point(c.x + rx * math.cos(2 * math.pi * i / n),
          c.y + ry * math.sin(2 * math.pi * i / n)),
  ];
}

/// True if [g] is a closed path (contains a `ClosePath` command) — such paths
/// (pie wedges, radar area rings, etc.) enclose a region that can be filled.
bool _pathIsClosed(PathGeometry g) => g.commands.any((c) => c is ClosePath);

/// Flattens a closed [PathGeometry] to an outline polygon (beziers sampled to
/// line segments) suitable for hachure clipping.
List<Point> _flattenPath(PathGeometry g) {
  final pts = <Point>[];
  Point? cur;
  for (final c in g.commands) {
    switch (c) {
      case MoveTo(:final p):
        cur = p;
        pts.add(p);
      case LineTo(:final p):
        pts.add(p);
        cur = p;
      case CubicTo(:final c1, :final c2, :final p):
        if (cur != null) {
          const steps = 8;
          for (var i = 1; i <= steps; i++) {
            pts.add(_cubic(cur, c1, c2, p, i / steps));
          }
        }
        cur = p;
      case QuadTo(:final c, :final p):
        if (cur != null) {
          const steps = 6;
          for (var i = 1; i <= steps; i++) {
            pts.add(_quad(cur, c, p, i / steps));
          }
        }
        cur = p;
      case ClosePath():
        break;
    }
  }
  return pts;
}

Point _cubic(Point p0, Point p1, Point p2, Point p3, double t) {
  final u = 1 - t;
  final a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
  return Point(a * p0.x + b * p1.x + c * p2.x + d * p3.x,
      a * p0.y + b * p1.y + c * p2.y + d * p3.y);
}

Point _quad(Point p0, Point p1, Point p2, double t) {
  final u = 1 - t;
  return Point(u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
      u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y);
}
