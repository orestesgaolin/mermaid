import 'package:elk/elk.dart';
import 'package:test/test.dart';

/// Returns the bounding rect (l, t, r, b) of a node by id from a result.
({double l, double t, double r, double b}) _rect(ElkResult res, String id) {
  final n = res.nodesById[id]!;
  return (l: n.x, t: n.y, r: n.x + n.width, b: n.y + n.height);
}

bool _overlaps(ElkResult res, String a, String b) {
  final ra = _rect(res, a), rb = _rect(res, b);
  return ra.l < rb.r && rb.l < ra.r && ra.t < rb.b && rb.t < ra.b;
}

void main() {
  group('ElkLayered (Phase 0 — flat layered layout)', () {
    test('places all nodes and returns positive bounds', () {
      final res = const ElkLayered().layout(ElkGraph(
        children: [
          ElkNode(id: 'a', width: 80, height: 40),
          ElkNode(id: 'b', width: 80, height: 40),
          ElkNode(id: 'c', width: 80, height: 40),
        ],
        edges: [
          ElkEdge(id: 'e1', sources: ['a'], targets: ['b']),
          ElkEdge(id: 'e2', sources: ['a'], targets: ['c']),
        ],
      ));

      expect(res.children.map((n) => n.id).toSet(), {'a', 'b', 'c'});
      expect(res.width, greaterThan(0));
      expect(res.height, greaterThan(0));
      for (final n in res.children) {
        expect(n.width, 80);
        expect(n.height, 40);
      }
    });

    test('respects flow direction: child sits below parent for DOWN', () {
      final res = const ElkLayered().layout(ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
        children: [
          ElkNode(id: 'a', width: 80, height: 40),
          ElkNode(id: 'b', width: 80, height: 40),
        ],
        edges: [ElkEdge(id: 'e1', sources: ['a'], targets: ['b'])],
      ));
      final a = res.nodesById['a']!, b = res.nodesById['b']!;
      expect(b.y, greaterThan(a.y));
    });

    test('child sits to the right of parent for RIGHT', () {
      final res = const ElkLayered().layout(ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
        children: [
          ElkNode(id: 'a', width: 80, height: 40),
          ElkNode(id: 'b', width: 80, height: 40),
        ],
        edges: [ElkEdge(id: 'e1', sources: ['a'], targets: ['b'])],
      ));
      final a = res.nodesById['a']!, b = res.nodesById['b']!;
      expect(b.x, greaterThan(a.x));
    });

    test('nodes do not overlap', () {
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
      final ids = ['a', 'b', 'c', 'd'];
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          expect(_overlaps(res, ids[i], ids[j]), isFalse,
              reason: '${ids[i]} overlaps ${ids[j]}');
        }
      }
    });

    test('edges carry a section with start and end points', () {
      final res = const ElkLayered().layout(ElkGraph(
        children: [
          ElkNode(id: 'a', width: 80, height: 40),
          ElkNode(id: 'b', width: 80, height: 40),
        ],
        edges: [ElkEdge(id: 'e1', sources: ['a'], targets: ['b'])],
      ));
      final e = res.edges.single;
      expect(e.sections, hasLength(1));
      expect(e.sections.first.points.length, greaterThanOrEqualTo(2));
    });
  });
}
