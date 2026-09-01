import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

void main() {
  group('distanceToPath', () {
    test('measures line, quadratic, cubic, close, and empty paths', () {
      expect(
        distanceToPath(
          const PathGeometry([MoveTo(Point(0, 0)), LineTo(Point(10, 0))]),
          const Point(5, 3),
        ),
        closeTo(3, 1e-9),
      );
      expect(
        distanceToPath(
          const PathGeometry([
            MoveTo(Point(0, 0)),
            QuadTo(Point(5, 10), Point(10, 0)),
          ]),
          const Point(5, 5),
        ),
        lessThan(0.01),
      );
      expect(
        distanceToPath(
          const PathGeometry([
            MoveTo(Point(0, 0)),
            CubicTo(Point(0, 10), Point(10, 10), Point(10, 0)),
          ]),
          const Point(5, 7.5),
        ),
        lessThan(0.01),
      );
      expect(
        distanceToPath(
          const PathGeometry([
            MoveTo(Point(0, 0)),
            LineTo(Point(10, 0)),
            LineTo(Point(10, 10)),
            ClosePath(),
          ]),
          const Point(5, 5),
        ),
        lessThan(0.01),
      );
      expect(
        distanceToPath(const PathGeometry([MoveTo(Point(0, 0))]), Point.zero),
        double.infinity,
      );
    });

    test('rejects invalid curve flatness', () {
      const path = PathGeometry([MoveTo(Point.zero), LineTo(Point(1, 1))]);
      expect(() => distanceToPath(path, Point.zero, flatness: 0),
          throwsArgumentError);
      expect(() => distanceToPath(path, Point.zero, flatness: double.nan),
          throwsArgumentError);
    });
  });

  test('flowchart edge metadata keeps global declaration indices', () {
    const source = '''flowchart TD
  outside --> end
  subgraph nested
    direction LR
    from_id -->|parallel one| to_id
    from_id -->|parallel two| to_id
  end
  to_id --> outside
  hidden ~~~ end''';
    final scene = const Mermaid(
      measurer: ApproximateTextMeasurer(),
    ).render(source);
    final edges = _groups(scene.nodes)
        .where((group) => group.role == SceneGroupRole.edge)
        .toList();

    expect(
      edges.map((group) => group.edge?.linkIndex),
      containsAll(<int>[0, 1, 2, 3, 4]),
    );
    final nested = edges.firstWhere((group) => group.edge?.linkIndex == 1);
    expect(nested.edge?.fromId, 'from_id');
    expect(nested.edge?.toId, 'to_id');
    final hidden = edges.firstWhere((group) => group.edge?.linkIndex == 4);
    expect(hidden.children, isEmpty);

    final labels = _groups(scene.nodes)
        .where((group) => group.role == SceneGroupRole.edgeLabel)
        .toList();
    expect(labels.map((group) => group.edge?.linkIndex), containsAll([1, 2]));
  });

  test('hand-drawn rendering preserves edge metadata', () {
    final scene = const Mermaid(
      measurer: ApproximateTextMeasurer(),
    ).render("%%{init: {'look':'handDrawn','handDrawnSeed':7}}%%\n"
        'flowchart LR\nfrom_id --> to_id');
    final edge = _groups(scene.nodes).firstWhere(
      (group) => group.role == SceneGroupRole.edge,
    );

    expect(edge.edge?.fromId, 'from_id');
    expect(edge.edge?.toId, 'to_id');
    expect(edge.edge?.linkIndex, 0);
  });
}

Iterable<SceneGroup> _groups(Iterable<SceneNode> nodes) sync* {
  for (final node in nodes) {
    if (node is SceneGroup) {
      yield node;
      yield* _groups(node.children);
    }
  }
}
