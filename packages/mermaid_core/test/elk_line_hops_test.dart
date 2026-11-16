import 'package:mermaid_core/mermaid_core.dart';
import 'package:mermaid_core/src/line_jumps.dart';
import 'package:test/test.dart';

import 'support/scene.dart';

const _mermaid = Mermaid(measurer: ApproximateTextMeasurer());

const _crossingEdges = '''
flowchart TD
    A --> C
    A --> D
    B --> C
    B --> D
    A --> E
    B --> E
''';

String _elk(String lineHops) =>
    '---\nconfig:\n  layout: elk\n  elk:\n    lineHops: $lineHops\n---\n'
    '$_crossingEdges';

List<PathGeometry> _edgePaths(String source) => [
  for (final shape in shapesOf(_mermaid.render(source).nodes))
    if (shape.paintRole == ScenePaintRole.edgeStroke)
      shape.geometry as PathGeometry,
];

/// Each hop as (start, end) of the stretch the hop replaces.
List<(Point, Point, List<CubicTo>)> _arcHops(PathGeometry path) {
  final hops = <(Point, Point, List<CubicTo>)>[];
  final c = path.commands;
  for (var i = 1; i + 1 < c.length; i++) {
    final before = c[i - 1], first = c[i], second = c[i + 1];
    if (first is CubicTo && second is CubicTo && before is LineTo) {
      hops.add((before.p, second.p, [first, second]));
      i++;
    }
  }
  return hops;
}

/// True when two straight pieces meet at an angle with no curve between.
bool _hasSharpBend(PathGeometry path) {
  Point? last;
  Point? dir;
  for (final command in path.commands) {
    switch (command) {
      case MoveTo(:final p):
        last = p;
        dir = null;
      case LineTo(:final p):
        final d = p - last!;
        if (d.x.abs() + d.y.abs() > 1e-6) {
          final prev = dir;
          if (prev != null && (prev.x * d.y - prev.y * d.x).abs() > 1e-6) {
            return true;
          }
          dir = d;
        }
        last = p;
      case CubicTo(:final p) || QuadTo(:final p):
        last = p;
        dir = null;
      case ClosePath():
        break;
    }
  }
  return false;
}

double _distanceToOthers(List<PathGeometry> paths, PathGeometry own, Point p) {
  var best = double.infinity;
  for (final other in paths) {
    if (identical(other, own)) continue;
    final d = distanceToPath(other, p);
    if (d < best) best = d;
  }
  return best;
}

void main() {
  group('ELK line hops', () {
    test('a horizontal edge hops over each edge it crosses', () {
      final paths = _edgePaths(_elk('true'));
      final hops = [
        for (final path in paths)
          for (final hop in _arcHops(path)) (path, hop),
      ];
      expect(hops, isNotEmpty);
      for (final (path, (pre, post, curves)) in hops) {
        expect(pre.y, closeTo(post.y, 1e-9), reason: 'hops sit on horizontals');
        final radius = (post.x - pre.x).abs() / 2;
        expect(radius, inInclusiveRange(3.6, 6));
        final center = Point((pre.x + post.x) / 2, pre.y);
        expect(_distanceToOthers(paths, path, center), lessThan(0.5));
        expect(curves.first.p.x, closeTo(center.x, 1e-9));
        expect(curves.first.p.y, closeTo(center.y - radius, 1e-9));
      }
    });

    test('every bend is rounded', () {
      final paths = _edgePaths(_elk('true'));
      expect(
        paths.where((p) => p.commands.whereType<QuadTo>().isNotEmpty),
        isNotEmpty,
      );
      for (final path in paths) {
        expect(_hasSharpBend(path), isFalse);
      }
    });

  });

  group('roundedEdgePathsWithJumps', () {
    const horizontal = LineJumpEdge(
      points: [Point(0, 0), Point(100, 0)],
      drawPoints: [Point(0, 0), Point(100, 0)],
    );

    LineJumpEdge vertical(double x) => LineJumpEdge(
      points: [Point(x, -50), Point(x, 50)],
      drawPoints: [Point(x, -50), Point(x, 50)],
    );

    test('only the horizontal segment of a crossing hops', () {
      final paths = roundedEdgePathsWithJumps([vertical(50), horizontal]);
      expect(paths[0].whereType<CubicTo>(), isEmpty);
      final hops = _arcHops(PathGeometry(paths[1]));
      expect(hops, hasLength(1));
      expect(hops.single.$1, const Point(44, 0));
      expect(hops.single.$2, const Point(56, 0));
    });

    test('a leftward segment still hops upward', () {
      const leftward = LineJumpEdge(
        points: [Point(100, 0), Point(0, 0)],
        drawPoints: [Point(100, 0), Point(0, 0)],
      );
      final hop = _arcHops(
        PathGeometry(roundedEdgePathsWithJumps([leftward, vertical(50)])[0]),
      ).single;
      expect(hop.$3.first.p, const Point(50, -6));
    });

    test('hops next to each other share the room between them', () {
      final paths = roundedEdgePathsWithJumps([
        horizontal,
        vertical(50),
        vertical(58),
      ]);
      final hops = _arcHops(PathGeometry(paths[0]));
      expect(hops, hasLength(2));
      expect(hops[0].$2.x - hops[0].$1.x, closeTo(8, 1e-9));
      expect(hops[1].$2.x - hops[1].$1.x, closeTo(8, 1e-9));
    });

    test('a hop too close to a rounded bend is dropped', () {
      const bent = LineJumpEdge(
        points: [Point(0, 0), Point(100, 0), Point(100, 50)],
        drawPoints: [Point(0, 0), Point(100, 0), Point(100, 50)],
      );
      final roomy = roundedEdgePathsWithJumps([bent, vertical(80)]);
      expect(_arcHops(PathGeometry(roomy[0])), hasLength(1));
      final tight = roundedEdgePathsWithJumps([bent, vertical(91)]);
      expect(_arcHops(PathGeometry(tight[0])), isEmpty);
    });
  });
}
