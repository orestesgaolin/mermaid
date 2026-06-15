import 'package:elk_layout/elk_layout.dart';
import 'package:test/test.dart';

ElkGraph _chain(ElkLayoutOptions opts) => ElkGraph(
      layoutOptions: opts,
      children: [
        for (final id in ['a', 'b', 'c'])
          ElkNode(id: id, width: 80, height: 40),
      ],
      edges: [
        ElkEdge(id: 'e1', sources: ['a'], targets: ['b']),
        ElkEdge(id: 'e2', sources: ['b'], targets: ['c']),
      ],
    );

void main() {
  group('Phase 1 — ELK spacing model', () {
    test('baseValue-derived spacing differs from dagre 50/50 spacing', () {
      // ELK default base value 40 vs an explicit dagre-like 50.
      final elk = const ElkLayered().layout(_chain(const ElkLayoutOptions()));
      final dagreLike = const ElkLayered().layout(_chain(const ElkLayoutOptions(
        spacingNodeNode: 50,
        spacingNodeNodeBetweenLayers: 50,
      )));

      final elkGap = elk.nodesById['b']!.y - elk.nodesById['a']!.y;
      final dagreGap = dagreLike.nodesById['b']!.y - dagreLike.nodesById['a']!.y;
      expect((elkGap - dagreGap).abs(), greaterThan(1.0),
          reason: 'ELK spacing model should change inter-layer distance');
    });

    test('layout is deterministic', () {
      final a = const ElkLayered().layout(_chain(const ElkLayoutOptions()));
      final b = const ElkLayered().layout(_chain(const ElkLayoutOptions()));
      for (final id in ['a', 'b', 'c']) {
        expect(a.nodesById[id]!.x, b.nodesById[id]!.x);
        expect(a.nodesById[id]!.y, b.nodesById[id]!.y);
      }
    });
  });

  group('Phase 1 — model order', () {
    test('forceNodeModelOrder keeps siblings in declaration order', () {
      // a → {b, c, d}; declared b, c, d. Forcing model order should keep that
      // left-to-right order among the siblings on their layer.
      ElkGraph graph(bool force) => ElkGraph(
            layoutOptions: ElkLayoutOptions(forceNodeModelOrder: force),
            children: [
              for (final id in ['a', 'b', 'c', 'd'])
                ElkNode(id: id, width: 60, height: 40),
            ],
            edges: [
              ElkEdge(id: 'e1', sources: ['a'], targets: ['c']),
              ElkEdge(id: 'e2', sources: ['a'], targets: ['b']),
              ElkEdge(id: 'e3', sources: ['a'], targets: ['d']),
            ],
          );
      final forced = const ElkLayered().layout(graph(true));
      // b, c, d share a layer; with forced model order they keep b<c<d by x.
      final bx = forced.nodesById['b']!.x;
      final cx = forced.nodesById['c']!.x;
      final dx = forced.nodesById['d']!.x;
      expect(bx, lessThan(cx));
      expect(cx, lessThan(dx));
    });
  });
}
