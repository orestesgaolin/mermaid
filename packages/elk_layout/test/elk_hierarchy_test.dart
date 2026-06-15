import 'package:elk_layout/elk_layout.dart';
import 'package:test/test.dart';

void main() {
  group('Phase 3 — hierarchy / clusters', () {
    test('children are placed inside the parent cluster rect', () {
      final res = const ElkLayered().layout(ElkGraph(
        children: [
          ElkNode(id: 'outside', width: 80, height: 40),
          ElkNode(id: 'cluster', children: [
            ElkNode(id: 'c1', width: 80, height: 40),
            ElkNode(id: 'c2', width: 80, height: 40),
          ]),
        ],
        edges: [
          ElkEdge(id: 'e1', sources: ['c1'], targets: ['c2']),
          ElkEdge(id: 'e2', sources: ['outside'], targets: ['c1']),
        ],
      ));

      final byId = res.nodesById;
      final cluster = byId['cluster']!;
      final c1 = byId['c1']!;
      final c2 = byId['c2']!;

      // The cluster has a computed, positive size.
      expect(cluster.width, greaterThan(0));
      expect(cluster.height, greaterThan(0));

      // Both children sit within the cluster's absolute bounds.
      for (final c in [c1, c2]) {
        expect(c.x, greaterThanOrEqualTo(cluster.x - 0.5));
        expect(c.y, greaterThanOrEqualTo(cluster.y - 0.5));
        expect(c.x + c.width, lessThanOrEqualTo(cluster.x + cluster.width + 0.5));
        expect(c.y + c.height, lessThanOrEqualTo(cluster.y + cluster.height + 0.5));
      }
    });

    test('cluster rect encloses all members', () {
      final res = const ElkLayered().layout(ElkGraph(
        children: [
          ElkNode(id: 'g', children: [
            for (final id in ['a', 'b', 'c'])
              ElkNode(id: id, width: 60, height: 30),
          ]),
        ],
        edges: [
          ElkEdge(id: 'e1', sources: ['a'], targets: ['b']),
          ElkEdge(id: 'e2', sources: ['b'], targets: ['c']),
        ],
      ));
      final g = res.nodesById['g']!;
      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      for (final id in ['a', 'b', 'c']) {
        final n = res.nodesById[id]!;
        minX = n.x < minX ? n.x : minX;
        minY = n.y < minY ? n.y : minY;
        maxX = n.x + n.width > maxX ? n.x + n.width : maxX;
        maxY = n.y + n.height > maxY ? n.y + n.height : maxY;
      }
      expect(g.x, lessThanOrEqualTo(minX + 0.5));
      expect(g.y, lessThanOrEqualTo(minY + 0.5));
      expect(g.x + g.width, greaterThanOrEqualTo(maxX - 0.5));
      expect(g.y + g.height, greaterThanOrEqualTo(maxY - 0.5));
    });

    test('result tree nests children under the cluster node', () {
      final res = const ElkLayered().layout(ElkGraph(
        children: [
          ElkNode(id: 'cluster', children: [
            ElkNode(id: 'c1', width: 80, height: 40),
          ]),
        ],
      ));
      final cluster = res.children.singleWhere((n) => n.id == 'cluster');
      expect(cluster.children.map((n) => n.id), contains('c1'));
      // Child coordinates are parent-relative: within [0, cluster.size].
      final c1 = cluster.children.single;
      expect(c1.x, greaterThanOrEqualTo(-0.5));
      expect(c1.y, greaterThanOrEqualTo(-0.5));
    });
  });
}
