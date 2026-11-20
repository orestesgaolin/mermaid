/// Rounded bends and line hops for ELK edge routes, ported from upstream
/// `lineJump.ts` and `elk/lineHops.ts` (mermaid 12.3).
library;

import 'dart:math' as math;

import 'geometry.dart';
import 'ir/scene.dart';

/// How an ELK edge is drawn where it crosses another (`elk.lineHops`).
enum ElkLineHops {
  /// A half-circle hop (`true` or `"arc"`, the default).
  arc,

  /// A break in the line (`"gap"`).
  gap,

  /// A plain crossing (`false`).
  none,
}

const double _cornerRadius = 5;
const double _jumpRadius = 6;
const double _cornerEpsilon = 1e-5;
const double _cornerJumpClearance = 2;
const double _minUsefulRadiusRatio = 0.6;
const double _endpointEpsilon = 1e-6;

/// Cubic control distance for a quarter circle of radius 1.
const double _quarterArcKappa = 0.5522847498307936;

/// One edge route.
class LineJumpEdge {
  const LineJumpEdge({required this.points, required this.drawPoints});

  /// The route before marker shortening; crossings are found on it.
  final List<Point> points;

  /// The route shortened for the markers; the path is drawn through it.
  final List<Point> drawPoints;
}

/// The rounded path, with hops, for each of [edges].
List<List<PathCommand>> roundedEdgePathsWithJumps(
  List<LineJumpEdge> edges, {
  ElkLineHops hops = ElkLineHops.arc,
}) {
  final jumpsByEdge = List.generate(edges.length, (_) => <_Crossing>[]);
  if (hops != ElkLineHops.none) {
    for (final c in _findCrossings(edges)) {
      jumpsByEdge[c.edge].add(c);
    }
  }
  return [
    for (var i = 0; i < edges.length; i++)
      _rewritePath(edges[i].drawPoints, jumpsByEdge[i], hops),
  ];
}

class _Crossing {
  _Crossing(this.edge, this.segIndex, this.t, this.point);
  final int edge;
  final int segIndex;
  final double t;
  final Point point;
}

class _Jump {
  _Jump(this.t, this.point, this.d);
  final double t;
  final Point point;
  final double d;
  double r = _jumpRadius;
}

class _Corner {
  const _Corner(this.start, this.ctrl, this.end, this.cutLen);
  final Point start;
  final Point ctrl;
  final Point end;
  final double cutLen;
}

double _len(Point a, Point b) =>
    math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));

(Point, double, double)? _segmentIntersection(
  Point a1,
  Point a2,
  Point b1,
  Point b2,
) {
  final dxA = a2.x - a1.x, dyA = a2.y - a1.y;
  final dxB = b2.x - b1.x, dyB = b2.y - b1.y;
  final denom = dxA * dyB - dyA * dxB;
  if (denom == 0) return null;
  final dx = b1.x - a1.x, dy = b1.y - a1.y;
  final tA = (dx * dyB - dy * dxB) / denom;
  final tB = (dx * dyA - dy * dxA) / denom;
  if (tA <= _endpointEpsilon ||
      tA >= 1 - _endpointEpsilon ||
      tB <= _endpointEpsilon ||
      tB >= 1 - _endpointEpsilon) {
    return null;
  }
  return (Point(a1.x + tA * dxA, a1.y + tA * dyA), tA, tB);
}

bool _isHorizontal(Point a, Point b) => (b.x - a.x).abs() >= (b.y - a.y).abs();

_Corner? _roundedCorner(Point prev, Point curr, Point next) {
  final dx1 = curr.x - prev.x, dy1 = curr.y - prev.y;
  final dx2 = next.x - curr.x, dy2 = next.y - curr.y;
  final len1 = math.sqrt(dx1 * dx1 + dy1 * dy1);
  final len2 = math.sqrt(dx2 * dx2 + dy2 * dy2);
  if (len1 < _cornerEpsilon || len2 < _cornerEpsilon) return null;
  final nx1 = dx1 / len1, ny1 = dy1 / len1;
  final nx2 = dx2 / len2, ny2 = dy2 / len2;
  final dot = (nx1 * nx2 + ny1 * ny2).clamp(-1.0, 1.0);
  final angle = math.acos(dot);
  if (angle < _cornerEpsilon || (math.pi - angle).abs() < _cornerEpsilon) {
    return null;
  }
  final cutLen = math.min(
    _cornerRadius / math.sin(angle / 2),
    math.min(len1 / 2, len2 / 2),
  );
  return _Corner(
    Point(curr.x - nx1 * cutLen, curr.y - ny1 * cutLen),
    curr,
    Point(curr.x + nx2 * cutLen, curr.y + ny2 * cutLen),
    cutLen,
  );
}

bool _sitsInRoundedCorner(List<Point> pts, int seg, double t) {
  final a = pts[seg], b = pts[seg + 1];
  final segLen = _len(a, b);
  final d = t * segLen;
  final entering = seg > 0 ? _roundedCorner(pts[seg - 1], a, b) : null;
  if (entering != null && d < entering.cutLen) return true;
  final leaving = seg + 2 < pts.length
      ? _roundedCorner(a, b, pts[seg + 2])
      : null;
  return leaving != null && segLen - d < leaving.cutLen;
}

List<_Crossing> _findCrossings(List<LineJumpEdge> edges) {
  final crossings = <_Crossing>[];
  for (var i = 0; i < edges.length; i++) {
    final a = edges[i].points;
    for (var j = i + 1; j < edges.length; j++) {
      final b = edges[j].points;
      for (var si = 0; si < a.length - 1; si++) {
        for (var sj = 0; sj < b.length - 1; sj++) {
          final hit = _segmentIntersection(a[si], a[si + 1], b[sj], b[sj + 1]);
          if (hit == null) continue;
          final (point, tA, tB) = hit;
          if (_sitsInRoundedCorner(a, si, tA) ||
              _sitsInRoundedCorner(b, sj, tB)) {
            continue;
          }
          final aHoriz = _isHorizontal(a[si], a[si + 1]);
          final bHoriz = _isHorizontal(b[sj], b[sj + 1]);
          final jumpOnA = aHoriz != bHoriz && aHoriz;
          crossings.add(
            jumpOnA ? _Crossing(i, si, tA, point) : _Crossing(j, sj, tB, point),
          );
        }
      }
    }
  }
  return crossings;
}

List<PathCommand> _rewritePath(
  List<Point> points,
  List<_Crossing> crossings,
  ElkLineHops hops,
) {
  if (points.length < 2) {
    return [if (points.isNotEmpty) MoveTo(points.first)];
  }
  final segCount = points.length - 1;
  final bySeg = <int, List<_Jump>>{};
  for (final c in crossings) {
    if (c.segIndex >= segCount) continue;
    final segLen = _len(points[c.segIndex], points[c.segIndex + 1]);
    (bySeg[c.segIndex] ??= []).add(_Jump(c.t, c.point, c.t * segLen));
  }

  final out = <PathCommand>[MoveTo(points.first)];
  const minUseful = _jumpRadius * _minUsefulRadiusRatio;
  for (var i = 0; i < segCount; i++) {
    final a = points[i], b = points[i + 1];
    final segLen = _len(a, b);
    final ux = segLen == 0 ? 0.0 : (b.x - a.x) / segLen;
    final uy = segLen == 0 ? 0.0 : (b.y - a.y) / segLen;
    final consumed = i > 0
        ? _roundedCorner(points[i - 1], a, b)?.cutLen ?? 0.0
        : 0.0;
    final upcoming = i < segCount - 1
        ? _roundedCorner(a, b, points[i + 2])
        : null;
    final stop = segLen - (upcoming?.cutLen ?? 0);

    final jumps = [...?bySeg[i]]..sort((x, y) => x.t.compareTo(y.t));
    jumps.retainWhere((j) {
      final room = math.min(j.d - consumed, stop - j.d) - _cornerJumpClearance;
      j.r = math.min(j.r, room);
      return j.r >= minUseful;
    });
    for (var k = 0; k < jumps.length - 1; k++) {
      final gap = jumps[k + 1].d - jumps[k].d;
      if (jumps[k].r + jumps[k + 1].r > gap) {
        final half = gap / 2;
        jumps[k].r = math.min(jumps[k].r, half);
        jumps[k + 1].r = math.min(jumps[k + 1].r, half);
      }
    }
    // Horizontal hops bend up, vertical ones right (upstream's sweep flag).
    final u = Point(ux, uy);
    final sweep = _isHorizontal(a, b) ? ux >= 0 : uy >= 0;
    final bulge = sweep ? Point(uy, -ux) : Point(-uy, ux);
    for (final j in jumps) {
      if (j.r < minUseful) continue;
      final pre = j.point - u * j.r;
      final post = j.point + u * j.r;
      out.add(LineTo(pre));
      if (hops == ElkLineHops.gap) {
        out.add(MoveTo(post));
      } else {
        out.addAll(_halfCircle(pre, j.point, post, u, bulge, j.r));
      }
    }
    if (upcoming != null) {
      out
        ..add(LineTo(upcoming.start))
        ..add(QuadTo(upcoming.ctrl, upcoming.end));
    } else {
      out.add(LineTo(b));
    }
  }
  return out;
}

/// The half circle from [pre] to [post] as two cubics (the scene has no arc).
List<PathCommand> _halfCircle(
  Point pre,
  Point center,
  Point post,
  Point u,
  Point bulge,
  double r,
) {
  final k = _quarterArcKappa * r;
  final apex = center + bulge * r;
  return [
    CubicTo(pre + bulge * k, apex - u * k, apex),
    CubicTo(apex + u * k, post + bulge * k, post),
  ];
}
