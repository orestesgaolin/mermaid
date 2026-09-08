import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  for (final direction in ElkDirection.values) {
    test('asymmetric root padding in ${direction.name} uses output axes', () {
      final result = const ElkLayered().layout(
        ElkGraph.fromJson({
          'id': 'root',
          'layoutOptions': {
            'elk.direction': direction.name.toUpperCase(),
            'elk.padding': '[top=7,left=11,bottom=13,right=17]',
          },
          'children': [
            {'id': 'a', 'width': 80, 'height': 40},
          ],
        }),
      );
      expect(result.width, 108);
      expect(result.height, 60);
      expect(result.children.single.x, 11);
      expect(result.children.single.y, 7);
    });

    test(
      'padding preserves nested routes, ports and labels in ${direction.name}',
      () {
        final input = <String, dynamic>{
          'id': 'root',
          'layoutOptions': {'elk.direction': direction.name.toUpperCase()},
          'children': [
            {
              'id': 'cluster',
              'children': [
                {
                  'id': 'a',
                  'width': 80,
                  'height': 40,
                  'ports': [
                    {
                      'id': 'out',
                      'width': 8,
                      'height': 8,
                      'layoutOptions': {'elk.port.side': 'EAST'},
                    },
                  ],
                },
                {'id': 'b', 'width': 80, 'height': 40},
              ],
              'edges': [
                {
                  'id': 'ab',
                  'sources': ['out'],
                  'targets': ['b'],
                },
              ],
            },
            {'id': 'c', 'width': 80, 'height': 40},
          ],
          'edges': [
            {
              'id': 'bc',
              'sources': ['b'],
              'targets': ['c'],
              'labels': [
                {'text': 'done', 'width': 30, 'height': 12},
              ],
            },
            {
              'id': 'loop',
              'sources': ['c'],
              'targets': ['c'],
            },
          ],
        };
        final plain = const ElkLayered().layout(ElkGraph.fromJson(input));
        (input['layoutOptions'] as Map)['org.eclipse.elk.padding'] =
            '[top=7,left=11,bottom=13,right=17]';
        final padded = const ElkLayered().layout(ElkGraph.fromJson(input));
        expect(padded.width, closeTo(plain.width + 28, 0.001));
        expect(padded.height, closeTo(plain.height + 20, 0.001));
        for (final node in plain.nodesById.values) {
          final actual = padded.nodesById[node.id]!;
          expect(actual.x, closeTo(node.x + 11, 0.001));
          expect(actual.y, closeTo(node.y + 7, 0.001));
          for (var i = 0; i < node.ports.length; i++) {
            expect(actual.ports[i].x, node.ports[i].x);
            expect(actual.ports[i].y, node.ports[i].y);
          }
        }
        for (final edge in plain.edges) {
          final actual = padded.edges.singleWhere((e) => e.id == edge.id);
          final before = edge.sections.expand((s) => s.points).toList();
          final after = actual.sections.expand((s) => s.points).toList();
          expect(after, hasLength(before.length));
          for (var i = 0; i < before.length; i++) {
            expect(after[i].x, closeTo(before[i].x + 11, 0.001));
            expect(after[i].y, closeTo(before[i].y + 7, 0.001));
          }
          for (var i = 0; i < edge.labels.length; i++) {
            expect(actual.labels[i].x, closeTo(edge.labels[i].x + 11, 0.001));
            expect(actual.labels[i].y, closeTo(edge.labels[i].y + 7, 0.001));
          }
        }
      },
    );
  }
}
