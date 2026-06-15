import 'package:elk_layout/elk_layout.dart';
import 'package:test/test.dart';

/// Each consecutive segment of a section is axis-aligned (horizontal or
/// vertical) within tolerance.
bool _isOrthogonal(ElkEdgeSection s) {
  final pts = s.points;
  for (var i = 1; i < pts.length; i++) {
    final dx = (pts[i].x - pts[i - 1].x).abs();
    final dy = (pts[i].y - pts[i - 1].y).abs();
    if (dx > 0.6 && dy > 0.6) return false;
  }
  return true;
}

void main() {
  group('Phase 2 — orthogonal routing', () {
    test('routeOrthogonal turns a diagonal into axis-aligned bends', () {
      final s = routeOrthogonal(
        const [ElkPoint(0, 0), ElkPoint(40, 100)],
        vertical: true,
      );
      expect(_isOrthogonal(s), isTrue);
      expect(s.bendPoints, isNotEmpty);
      expect(s.startPoint.x, 0);
      expect(s.endPoint.x, 40);
    });

    test('collinear points are simplified away', () {
      final s = routeOrthogonal(
        const [ElkPoint(0, 0), ElkPoint(0, 50), ElkPoint(0, 100)],
        vertical: true,
      );
      expect(s.points, hasLength(2)); // straight line, no bends
      expect(s.bendPoints, isEmpty);
    });

    test('engine produces orthogonal sections for every edge', () {
      final res = const ElkLayered().layout(ElkGraph(
        children: [
          for (final id in ['a', 'b', 'c', 'd'])
            ElkNode(id: id, width: 80, height: 40),
        ],
        edges: [
          ElkEdge(id: 'e1', sources: ['a'], targets: ['b']),
          ElkEdge(id: 'e2', sources: ['a'], targets: ['c']),
          ElkEdge(id: 'e3', sources: ['b'], targets: ['d']),
          ElkEdge(id: 'e4', sources: ['c'], targets: ['d']),
        ],
      ));
      for (final e in res.edges) {
        for (final s in e.sections) {
          expect(_isOrthogonal(s), isTrue, reason: 'edge ${e.id} not orthogonal');
        }
      }
    });

    test('parallel edges between a pair occupy distinct lanes', () {
      final res = const ElkLayered().layout(ElkGraph(
        children: [
          ElkNode(id: 'a', width: 80, height: 40),
          ElkNode(id: 'b', width: 80, height: 40),
        ],
        edges: [
          ElkEdge(id: 'e1', sources: ['a'], targets: ['b']),
          ElkEdge(id: 'e2', sources: ['a'], targets: ['b']),
        ],
      ));
      final s1 = res.edges[0].sections.first;
      final s2 = res.edges[1].sections.first;
      // Their midpoints should differ (distinct channels).
      ElkPoint mid(ElkEdgeSection s) {
        final p = s.points;
        return p[p.length ~/ 2];
      }

      final m1 = mid(s1), m2 = mid(s2);
      expect((m1.x - m2.x).abs() + (m1.y - m2.y).abs(), greaterThan(1.0));
    });
  });
}
