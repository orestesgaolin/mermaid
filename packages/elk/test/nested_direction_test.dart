import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  group('nested direction overrides', () {
    for (final rootDirection in ElkDirection.values) {
      for (final childDirection in ElkDirection.values) {
        test('$rootDirection root with $childDirection child', () {
          final result = _nested(rootDirection, childDirection);
          final children = result.children.single.children;
          final a = children.singleWhere((node) => node.id == 'a');
          final b = children.singleWhere((node) => node.id == 'b');
          switch (childDirection) {
            case ElkDirection.right:
              expect(b.x, greaterThan(a.x));
            case ElkDirection.left:
              expect(b.x, lessThan(a.x));
            case ElkDirection.down:
              expect(b.y, greaterThan(a.y));
            case ElkDirection.up:
              expect(b.y, lessThan(a.y));
          }
          final edge = result.edges.single;
          expect(
            edge.sections.single.points,
            hasLength(greaterThanOrEqualTo(2)),
          );
          for (
            var index = 1;
            index < edge.sections.single.points.length;
            index++
          ) {
            final p = edge.sections.single.points[index - 1];
            final q = edge.sections.single.points[index];
            expect(p.x == q.x || p.y == q.y, isTrue);
          }
        });

        test('$rootDirection/$childDirection cross-boundary route', () {
          final result = _crossNested(rootDirection, childDirection);
          final cluster = result.children.singleWhere(
            (node) => node.id == 'cluster',
          );
          final source = cluster.children.singleWhere((node) => node.id == 'b');
          final outside = result.children.singleWhere(
            (node) => node.id == 'outside',
          );
          final points = result.edges
              .singleWhere((edge) => edge.id == 'cross')
              .sections
              .single
              .points;
          expect(
            _onBorder(points.first, (
              x: cluster.x + source.x,
              y: cluster.y + source.y,
              w: source.width,
              h: source.height,
            )),
            isTrue,
          );
          expect(
            _onBorder(points.last, (
              x: outside.x,
              y: outside.y,
              w: outside.width,
              h: outside.height,
            )),
            isTrue,
          );
          for (var index = 1; index < points.length; index++) {
            expect(
              points[index - 1].x == points[index].x ||
                  points[index - 1].y == points[index].y,
              isTrue,
              reason: '$rootDirection/$childDirection segment $index',
            );
          }
          final labels = result.edges
              .singleWhere((edge) => edge.id == 'cross')
              .labels;
          expect(
            labels
                .map((label) => (label.text, label.width, label.height))
                .toSet(),
            {('tail', 30.0, 10.0), ('head', 26.0, 8.0)},
          );
          _expectEndLabelBesideRoute(
            labels.singleWhere((label) => label.text == 'tail'),
            points,
          );
          _expectEndLabelBesideRoute(
            labels.singleWhere((label) => label.text == 'head'),
            points.reversed.toList(),
          );
        });
      }
    }

    test('fromJson preserves a nested direction override', () {
      final graph = ElkGraph.fromJson({
        'id': 'root',
        'layoutOptions': {'elk.direction': 'RIGHT'},
        'children': [
          {
            'id': 'cluster',
            'layoutOptions': {'elk.direction': 'DOWN'},
            'children': [
              {'id': 'a', 'width': 40, 'height': 20},
              {'id': 'b', 'width': 40, 'height': 20},
            ],
            'edges': [
              {
                'id': 'ab',
                'sources': ['a'],
                'targets': ['b'],
              },
            ],
          },
        ],
      });
      final children = const ElkLayered()
          .layout(graph)
          .children
          .single
          .children;
      expect(children[1].y, greaterThan(children[0].y));
      expect(children[1].x, children[0].x);
    });

    test('explicit parent direction matches inherited default exactly', () {
      final inherited = _nested(ElkDirection.right, null);
      final explicit = _nested(ElkDirection.right, ElkDirection.right);
      expect(_geometry(explicit), _geometry(inherited));
    });

    test('transforms nested declared port sides and anchors', () {
      final result = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
          children: [
            ElkNode(
              id: 'cluster',
              layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
              children: [
                ElkNode(
                  id: 'a',
                  width: 40,
                  height: 20,
                  ports: [ElkPort(id: 'a-out', side: ElkPortSide.south)],
                ),
                ElkNode(
                  id: 'b',
                  width: 40,
                  height: 20,
                  ports: [ElkPort(id: 'b-in', side: ElkPortSide.north)],
                ),
              ],
              edges: [
                ElkEdge(id: 'ab', sources: ['a-out'], targets: ['b-in']),
              ],
            ),
          ],
        ),
      );
      final children = result.children.single.children;
      final a = children.singleWhere((node) => node.id == 'a');
      final b = children.singleWhere((node) => node.id == 'b');
      expect(a.ports.single.y, a.height);
      expect(b.ports.single.y, 0);
      final section = result.edges.single.sections.single;
      expect(section.startPoint.y, a.y + a.height + result.children.single.y);
      expect(section.endPoint.y, b.y + result.children.single.y);
    });

    test('deep override keeps labels contained and cross edge connected', () {
      final result = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
          children: [
            ElkNode(
              id: 'outer',
              labels: [ElkLabel(text: 'Outer', width: 44, height: 14)],
              children: [
                ElkNode(
                  id: 'inner',
                  layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
                  labels: [ElkLabel(text: 'Inner', width: 40, height: 12)],
                  children: [
                    ElkNode(id: 'a', width: 44, height: 24),
                    ElkNode(id: 'b', width: 38, height: 28),
                  ],
                  edges: [
                    ElkEdge(id: 'ab', sources: ['a'], targets: ['b']),
                  ],
                ),
              ],
            ),
            ElkNode(id: 'outside', width: 50, height: 24),
          ],
          edges: [
            ElkEdge(id: 'cross', sources: ['b'], targets: ['outside']),
          ],
        ),
      );
      final outer = result.children.singleWhere((node) => node.id == 'outer');
      final inner = outer.children.single;
      final a = inner.children.singleWhere((node) => node.id == 'a');
      final b = inner.children.singleWhere((node) => node.id == 'b');
      expect(b.y, greaterThan(a.y));
      for (final entry in [(outer, 0.0, 0.0), (inner, outer.x, outer.y)]) {
        for (final label in entry.$1.labels) {
          expect(label.x, inInclusiveRange(0, entry.$1.width - label.width));
          expect(label.y, inInclusiveRange(0, entry.$1.height - label.height));
        }
      }
      final cross = result.edges.singleWhere((edge) => edge.id == 'cross');
      final points = cross.sections.single.points;
      expect(points, hasLength(greaterThanOrEqualTo(2)));
      expect(
        points.every((point) => point.x.isFinite && point.y.isFinite),
        isTrue,
      );
      final absoluteB = (
        x: outer.x + inner.x + b.x,
        y: outer.y + inner.y + b.y,
        w: b.width,
        h: b.height,
      );
      final outside = result.children.singleWhere(
        (node) => node.id == 'outside',
      );
      expect(_onBorder(points.first, absoluteB), isTrue);
      expect(
        _onBorder(points.last, (
          x: outside.x,
          y: outside.y,
          w: outside.width,
          h: outside.height,
        )),
        isTrue,
      );
      for (var index = 1; index < points.length; index++) {
        expect(
          points[index - 1].x == points[index].x ||
              points[index - 1].y == points[index].y,
          isTrue,
        );
      }
    });

    test('three contrasting hierarchy frames preserve every local flow', () {
      final result = const ElkLayered().layout(
        ElkGraph(
          layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
          children: [
            ElkNode(
              id: 'outer',
              layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
              children: [
                ElkNode(
                  id: 'inner',
                  layoutOptions: ElkLayoutOptions(direction: ElkDirection.left),
                  children: [
                    ElkNode(id: 'a', width: 40, height: 20),
                    ElkNode(id: 'b', width: 40, height: 20),
                  ],
                  edges: [
                    ElkEdge(id: 'ab', sources: ['a'], targets: ['b']),
                  ],
                ),
                ElkNode(id: 'c', width: 52, height: 22),
              ],
              edges: [
                ElkEdge(id: 'inner-c', sources: ['inner'], targets: ['c']),
              ],
            ),
            ElkNode(id: 'outside', width: 48, height: 30),
          ],
          edges: [
            ElkEdge(
              id: 'b-outside',
              sources: ['b'],
              targets: ['outside'],
              labels: [
                ElkLabel(
                  text: 'TAIL 30x10',
                  width: 30,
                  height: 10,
                  placement: ElkEdgeLabelPlacement.tail,
                ),
                ElkLabel(
                  text: 'HEAD 26x8',
                  width: 26,
                  height: 8,
                  placement: ElkEdgeLabelPlacement.head,
                ),
              ],
            ),
          ],
        ),
      );
      final outer = result.children.singleWhere((node) => node.id == 'outer');
      final outside = result.children.singleWhere(
        (node) => node.id == 'outside',
      );
      final inner = outer.children.singleWhere((node) => node.id == 'inner');
      final c = outer.children.singleWhere((node) => node.id == 'c');
      final a = inner.children.singleWhere((node) => node.id == 'a');
      final b = inner.children.singleWhere((node) => node.id == 'b');
      expect(outside.x, greaterThan(outer.x));
      expect(c.y, greaterThan(inner.y));
      expect(b.x, lessThan(a.x));
      final cross = result.edges.singleWhere((edge) => edge.id == 'b-outside');
      final points = cross.sections.single.points;
      _expectEndLabelBesideRoute(
        cross.labels.singleWhere((label) => label.text == 'TAIL 30x10'),
        points,
      );
      _expectEndLabelBesideRoute(
        cross.labels.singleWhere((label) => label.text == 'HEAD 26x8'),
        points.reversed.toList(),
      );
    });
  });
}

ElkResult _nested(ElkDirection root, ElkDirection? child) =>
    const ElkLayered().layout(
      ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: root),
        children: [
          ElkNode(
            id: 'cluster',
            layoutOptions: child == null
                ? null
                : ElkLayoutOptions(direction: child),
            children: [
              ElkNode(id: 'a', width: 40, height: 20),
              ElkNode(id: 'b', width: 40, height: 20),
            ],
            edges: [
              ElkEdge(id: 'ab', sources: ['a'], targets: ['b']),
            ],
          ),
        ],
      ),
    );

ElkResult _crossNested(ElkDirection root, ElkDirection child) =>
    const ElkLayered().layout(
      ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: root),
        children: [
          ElkNode(
            id: 'cluster',
            layoutOptions: ElkLayoutOptions(direction: child),
            children: [
              ElkNode(id: 'a', width: 40, height: 20),
              ElkNode(id: 'b', width: 40, height: 20),
            ],
            edges: [
              ElkEdge(id: 'ab', sources: ['a'], targets: ['b']),
            ],
          ),
          ElkNode(id: 'outside', width: 40, height: 20),
        ],
        edges: [
          ElkEdge(
            id: 'cross',
            sources: ['b'],
            targets: ['outside'],
            labels: [
              ElkLabel(
                text: 'tail',
                width: 30,
                height: 10,
                placement: ElkEdgeLabelPlacement.tail,
              ),
              ElkLabel(
                text: 'head',
                width: 26,
                height: 8,
                placement: ElkEdgeLabelPlacement.head,
              ),
            ],
          ),
        ],
      ),
    );

List<Object> _geometry(ElkResult result) => [
  result.width,
  result.height,
  for (final node in result.children) ...[
    node.x,
    node.y,
    node.width,
    node.height,
    for (final child in node.children) ...[
      child.x,
      child.y,
      child.width,
      child.height,
    ],
  ],
  for (final edge in result.edges)
    for (final section in edge.sections)
      for (final point in section.points) ...[point.x, point.y],
];

bool _onBorder(
  ElkPoint point,
  ({double x, double y, double w, double h}) rect,
) {
  const epsilon = 1e-6;
  final withinX =
      point.x >= rect.x - epsilon && point.x <= rect.x + rect.w + epsilon;
  final withinY =
      point.y >= rect.y - epsilon && point.y <= rect.y + rect.h + epsilon;
  return (withinY &&
          ((point.x - rect.x).abs() <= epsilon ||
              (point.x - rect.x - rect.w).abs() <= epsilon)) ||
      (withinX &&
          ((point.y - rect.y).abs() <= epsilon ||
              (point.y - rect.y - rect.h).abs() <= epsilon));
}

void _expectEndLabelBesideRoute(
  ElkPositionedLabel label,
  List<ElkPoint> route,
) {
  final start = route.first;
  final end = route
      .skip(1)
      .firstWhere(
        (point) => point.x != start.x || point.y != start.y,
        orElse: () => route.last,
      );
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  if (dx.abs() >= dy.abs()) {
    expect(
      dx >= 0 ? label.x >= start.x : label.x + label.width <= start.x,
      isTrue,
    );
    expect(label.y + label.height <= start.y, isTrue);
  } else {
    expect(
      dy >= 0 ? label.y >= start.y : label.y + label.height <= start.y,
      isTrue,
    );
    expect(label.x + label.width <= start.x, isTrue);
  }
}
