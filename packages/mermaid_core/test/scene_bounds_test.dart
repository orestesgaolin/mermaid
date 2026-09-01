import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

const _style = TextStyleSpec(fontFamily: 'sans-serif', fontSize: 12);

void main() {
  group('RenderScene node bounds', () {
    test(
      'reports nested nodes and excludes non-node roles and empty groups',
      () {
        final scene = RenderScene(
          size: const Size(200, 160),
          nodes: [
            SceneGroup(
              id: 'cluster',
              role: SceneGroupRole.cluster,
              children: [
                const SceneShape(
                  geometry: RectGeometry(Rect.fromLTWH(0, 0, 150, 120)),
                ),
                SceneGroup(
                  id: 'nested',
                  children: const [
                    SceneShape(
                      geometry: RectGeometry(Rect.fromLTWH(20, 30, 40, 24)),
                    ),
                  ],
                ),
              ],
            ),
            const SceneGroup(
              id: 'edge_a_b_0',
              role: SceneGroupRole.edge,
              children: [
                SceneShape(
                  geometry: PathGeometry([
                    MoveTo(Point(0, 0)),
                    LineTo(Point(100, 100)),
                  ]),
                ),
              ],
            ),
            const SceneGroup(
              id: 'edgelabel_a_b_0',
              role: SceneGroupRole.edgeLabel,
              children: [
                SceneText(
                  text: 'edge',
                  bounds: Rect.fromLTWH(70, 70, 30, 12),
                  style: _style,
                  color: Color(0xff000000),
                ),
              ],
            ),
            const SceneGroup(id: 'empty', children: []),
          ],
        );

      expect(scene.nodeBounds, {
        'nested': const Rect.fromLTWH(20, 30, 40, 24),
      });
      expect(scene.boundsOf('nested'), scene.nodeBounds['nested']);
      expect(scene.boundsOfNode('nested'), scene.nodeBounds['nested']);
        expect(scene.boundsOfNode('cluster'), isNull);
        expect(scene.boundsOfNode('edge_a_b_0'), isNull);
        expect(scene.boundsOfNode('edgelabel_a_b_0'), isNull);
        expect(scene.boundsOfNode('empty'), isNull);
        expect(scene.boundsOfNode('missing'), isNull);
        expect(
          () => scene.nodeBounds['new'] = const Rect.fromLTWH(0, 0, 1, 1),
          throwsUnsupportedError,
        );
      },
    );

    test('last-painted duplicate node id wins', () {
      const first = Rect.fromLTWH(10, 10, 20, 20);
      const last = Rect.fromLTWH(80, 90, 30, 40);
      const scene = RenderScene(
        size: Size(140, 150),
        nodes: [
          SceneGroup(
            id: 'duplicate',
            children: [SceneShape(geometry: RectGeometry(first))],
          ),
          SceneGroup(
            id: 'duplicate',
            children: [SceneShape(geometry: RectGeometry(last))],
          ),
        ],
      );

      expect(scene.boundsOfNode('duplicate'), last);
    });

    test('flowchart lookup matches emitted node geometry only', () {
      final scene = Mermaid(measurer: const ApproximateTextMeasurer()).render(
        '''
flowchart TD
  n1["First"] -->|next| n2["Second"]
''',
      );
      final n1 = _findGroup(scene.nodes, 'n1');
      final n2 = _findGroup(scene.nodes, 'n2');

      expect(scene.boundsOfNode('n1'), sceneBounds(n1.children));
      expect(scene.boundsOfNode('n2'), sceneBounds(n2.children));
      expect(scene.nodeBounds.keys, containsAll(['n1', 'n2']));
      expect(scene.nodeBounds.keys, isNot(contains('edge_n1_n2_0')));
      expect(scene.nodeBounds.keys, isNot(contains('edgelabel_n1_n2_0')));
    });
  });
}

SceneGroup _findGroup(Iterable<SceneNode> nodes, String id) {
  for (final node in nodes) {
    if (node is! SceneGroup) continue;
    if (node.id == id) return node;
    try {
      return _findGroup(node.children, id);
    } on StateError {
      // Continue with the next sibling.
    }
  }
  throw StateError('No scene group with id $id');
}
