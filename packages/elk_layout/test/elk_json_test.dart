import 'dart:convert';

import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  group('ElkGraph.fromJson (elkjs JSON)', () {
    test('parses options, children, edges and lays out', () {
      final graph = ElkGraph.fromJson(jsonDecode('''
        {
          "id": "root",
          "layoutOptions": { "elk.algorithm": "layered", "elk.direction": "RIGHT" },
          "children": [
            { "id": "a", "width": 80, "height": 40 },
            { "id": "b", "width": 80, "height": 40 }
          ],
          "edges": [ { "id": "e1", "sources": ["a"], "targets": ["b"] } ]
        }
      ''') as Map<String, dynamic>);

      expect(graph.layoutOptions.direction, ElkDirection.right);
      expect(graph.children.map((n) => n.id), ['a', 'b']);
      expect(graph.edges.single.source, 'a');

      final res = const ElkLayered().layout(graph);
      // RIGHT flow: b is to the right of a.
      expect(res.nodesById['b']!.x, greaterThan(res.nodesById['a']!.x));
    });

    test('parses nested children and ports', () {
      final graph = ElkGraph.fromJson(jsonDecode('''
        {
          "children": [
            { "id": "g", "children": [ { "id": "c1", "width": 50, "height": 30 } ] },
            { "id": "n", "width": 50, "height": 30,
              "ports": [ { "id": "p", "layoutOptions": { "port.side": "EAST" } } ] }
          ],
          "edges": [ { "id": "e", "sources": ["p"], "targets": ["c1"] } ]
        }
      ''') as Map<String, dynamic>);

      expect(graph.children.first.isCompound, isTrue);
      expect(graph.children[1].ports.single.side, ElkPortSide.east);

      // Explicit ports are now supported. The graph lays out: "n" has an
      // explicit port "p" on its EAST border; the edge from "p" to "c1" routes
      // through that port.
      final portRes = const ElkLayered().layout(graph);
      final n = portRes.nodesById['n']!;
      // Port "p" is declared with side EAST: it should appear on n's east border.
      expect(n.ports, hasLength(1));
      expect(n.ports.single.id, 'p');
      expect(n.ports.single.x, closeTo(n.width, 0.5),
          reason: 'declared EAST port should be on east border');
      // The edge is routed (may have been skipped as cross-level if "c1" is
      // inside the compound "g" — the engine routes cross-level edges to the
      // cluster boundary, so the edge may or may not be present in the result,
      // but the graph itself must lay out without throwing).

      // The compound node ("g") on its own lays out: its child is nested.
      final hierarchyOnly = ElkGraph.fromJson(jsonDecode('''
        {
          "children": [
            { "id": "g", "children": [
              { "id": "c1", "width": 50, "height": 30 },
              { "id": "c2", "width": 50, "height": 30 }
            ] }
          ],
          "edges": [ { "id": "e", "sources": ["c1"], "targets": ["c2"] } ]
        }
      ''') as Map<String, dynamic>);
      final res = const ElkLayered().layout(hierarchyOnly);
      expect(res.nodesById['c1'], isNotNull);
      final g = res.children.single;
      expect(g.id, 'g');
      expect(g.children.map((n) => n.id), containsAll(['c1', 'c2']));
    });
  });
}
