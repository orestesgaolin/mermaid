import 'package:elk/elk.dart';
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

    test('deep target reaches leaf and retains positioned label', () {
      final res = const ElkLayered().layout(ElkGraph(
        children: [
          ElkNode(id: 'outside', width: 80, height: 40),
          ElkNode(id: 'outer', children: [
            ElkNode(id: 'inner', children: [
              ElkNode(id: 'leaf', width: 80, height: 40),
            ]),
          ]),
        ],
        edges: [
          ElkEdge(id: 'deep', sources: ['outside'], targets: ['leaf'], labels: [
            ElkLabel(text: 'deep label', width: 64, height: 16),
          ]),
        ],
      ));

      final edge = res.edges.singleWhere((e) => e.id == 'deep');
      expect(_onBoundary(edge.sections.single.endPoint, res.nodesById['leaf']!),
          isTrue,
          reason: 'the target must reach leaf, not an enclosing cluster');
      final label = edge.labels.single;
      expect((label.text, label.width, label.height), ('deep label', 64, 16));
      expect(label.x.isFinite && label.y.isFinite, isTrue);
      expect(label.x, inInclusiveRange(0, res.width - label.width));
      expect(label.y, inInclusiveRange(0, res.height - label.height));
    });

    test('deep source starts at leaf through every cluster level', () {
      final res = const ElkLayered().layout(ElkGraph(
        children: [
          ElkNode(id: 'outer', children: [
            ElkNode(id: 'inner', children: [
              ElkNode(id: 'leaf', width: 80, height: 40),
            ]),
          ]),
          ElkNode(id: 'outside', width: 80, height: 40),
        ],
        edges: [
          ElkEdge(id: 'deep', sources: ['leaf'], targets: ['outside']),
        ],
      ));

      final edge = res.edges.singleWhere((e) => e.id == 'deep');
      expect(_onBoundary(edge.sections.single.startPoint, res.nodesById['leaf']!),
          isTrue,
          reason: 'the source must start at leaf, not an enclosing cluster');
      expect(edge.sections.single.points.length, greaterThanOrEqualTo(4),
          reason: 'the stitched route must cross both cluster boundaries');
    });
  });
}

bool _onBoundary(ElkPoint point, ElkPositionedNode node) {
  const tolerance = 0.75;
  final onVertical =
      ((point.x - node.x).abs() <= tolerance ||
          (point.x - (node.x + node.width)).abs() <= tolerance) &&
      point.y >= node.y - tolerance &&
      point.y <= node.y + node.height + tolerance;
  final onHorizontal =
      ((point.y - node.y).abs() <= tolerance ||
          (point.y - (node.y + node.height)).abs() <= tolerance) &&
      point.x >= node.x - tolerance &&
      point.x <= node.x + node.width + tolerance;
  return onVertical || onHorizontal;
}
