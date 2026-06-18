/// Orthogonal (Manhattan) edge routing — the characteristic ELK look.
///
/// The layered pipeline produces, for each edge, a polyline that visits the
/// edge's dummy nodes (placed at each intermediate layer). This router turns
/// that polyline into an axis-aligned path: edges leave a node perpendicular
/// to its border, step through the inter-layer channels, and enter the target
/// perpendicular to its border. Diagonal segments become L/Z bends at the
/// channel midline between consecutive points.
library;

import '../api/result.dart';

/// Routes [polyline] (ordered points from source border, through dummies, to
/// target border) as an orthogonal [ElkEdgeSection]. [vertical] is true for
/// DOWN/UP layouts (edges flow along Y), false for RIGHT/LEFT (along X).
///
/// An optional [lane] offset nudges the cross-axis channel so parallel routes
/// between the same layers don't coincide.
ElkEdgeSection routeOrthogonal(
  List<ElkPoint> polyline, {
  required bool vertical,
  double lane = 0,
}) {
  if (polyline.length < 2) {
    final p = polyline.isEmpty ? const ElkPoint(0, 0) : polyline.first;
    return ElkEdgeSection(startPoint: p, endPoint: p);
  }

  final out = <ElkPoint>[polyline.first];
  for (var i = 1; i < polyline.length; i++) {
    final prev = out.last;
    final cur = polyline[i];
    final dx = (prev.x - cur.x).abs();
    final dy = (prev.y - cur.y).abs();
    if (dx > _eps && dy > _eps) {
      // Insert a right-angle bend at the channel midline between prev and cur.
      if (vertical) {
        final midY = (prev.y + cur.y) / 2 + lane;
        out.add(ElkPoint(prev.x, midY));
        out.add(ElkPoint(cur.x, midY));
      } else {
        final midX = (prev.x + cur.x) / 2 + lane;
        out.add(ElkPoint(midX, prev.y));
        out.add(ElkPoint(midX, cur.y));
      }
    }
    out.add(cur);
  }

  final cleaned = _dedupeCollinear(out);
  return ElkEdgeSection(
    startPoint: cleaned.first,
    endPoint: cleaned.last,
    bendPoints: cleaned.sublist(1, cleaned.length - 1),
  );
}

const double _eps = 0.5;

/// Drops points that are duplicates or lie on a straight run between their
/// neighbours, so the resulting path has only genuine corners.
List<ElkPoint> _dedupeCollinear(List<ElkPoint> pts) {
  final out = <ElkPoint>[];
  for (final p in pts) {
    if (out.isNotEmpty) {
      final last = out.last;
      if ((p.x - last.x).abs() < _eps && (p.y - last.y).abs() < _eps) {
        continue; // duplicate
      }
    }
    if (out.length >= 2) {
      final a = out[out.length - 2];
      final b = out[out.length - 1];
      // a-b-p collinear (both horizontal or both vertical)? replace b with p.
      final abV = (a.x - b.x).abs() < _eps;
      final bpV = (b.x - p.x).abs() < _eps;
      final abH = (a.y - b.y).abs() < _eps;
      final bpH = (b.y - p.y).abs() < _eps;
      if ((abV && bpV) || (abH && bpH)) {
        out[out.length - 1] = p;
        continue;
      }
    }
    out.add(p);
  }
  if (out.length < 2) return pts; // degenerate; keep original
  return out;
}
