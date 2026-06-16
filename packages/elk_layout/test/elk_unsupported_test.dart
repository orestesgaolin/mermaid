import 'package:elk_layout/elk_layout.dart';
import 'package:test/test.dart';

/// The faithful engine has NO dagre fallback: features it hasn't ported yet
/// throw a descriptive [UnsupportedError] rather than silently producing a
/// non-ELK layout. These tests pin that honest behavior; each will be replaced
/// with a real layout test as the corresponding feature lands (PORTING.md).
void main() {
  group('no fallback — unsupported features are indicated, not faked', () {
    test('hierarchy (compound nodes) — now supported, lays out', () {
      // Hierarchy (RECURSIVE / SEPARATE_CHILDREN) is implemented, so a compound
      // graph no longer throws; it lays out with the child nested under "g".
      final res = const ElkLayered().layout(const ElkGraph(children: [
        ElkNode(id: 'g', children: [ElkNode(id: 'c', width: 40, height: 20)]),
      ]));
      final g = res.children.single;
      expect(g.id, 'g');
      expect(g.children.single.id, 'c');
      expect(
        elkUnsupportedFeature(const ElkGraph(children: [
          ElkNode(
              id: 'g', children: [ElkNode(id: 'c', width: 40, height: 20)]),
        ])),
        isNull,
      );
    });

    test('explicit ports — now supported, lays out', () {
      // Explicit ports are now supported; the graph lays out without throwing.
      const graph = ElkGraph(children: [
        ElkNode(id: 'n', width: 40, height: 20, ports: [ElkPort(id: 'p')]),
      ]);
      final res = const ElkLayered().layout(graph);
      final n = res.nodesById['n']!;
      expect(n.ports, hasLength(1));
      expect(n.ports.single.id, 'p');
      expect(elkUnsupportedFeature(graph), isNull);
    });

    test('self-loops — now supported, route as an orthogonal loop', () {
      final res = const ElkLayered().layout(const ElkGraph(
        children: [ElkNode(id: 'a', width: 40, height: 20)],
        edges: [ElkEdge(id: 'e', sources: ['a'], targets: ['a'])],
      ));
      final loop = res.edges.singleWhere((e) => e.id == 'e');
      expect(loop.sections.first.points.length, greaterThanOrEqualTo(2));
    });

    test('model order — now supported', () {
      final res = const ElkLayered().layout(const ElkGraph(
        layoutOptions: ElkLayoutOptions(forceNodeModelOrder: true),
        children: [ElkNode(id: 'a', width: 40, height: 20)],
      ));
      expect(res.children.single.id, 'a');
    });

    test('elkUnsupportedFeature reports null for a supported graph', () {
      expect(
        elkUnsupportedFeature(const ElkGraph(
          children: [
            ElkNode(id: 'a', width: 40, height: 20),
            ElkNode(id: 'b', width: 40, height: 20),
          ],
          edges: [ElkEdge(id: 'e', sources: ['a'], targets: ['b'])],
        )),
        isNull,
      );
    });
  });
}
