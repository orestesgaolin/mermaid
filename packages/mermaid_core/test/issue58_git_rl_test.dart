import 'package:mermaid_core/mermaid_core.dart';
import 'package:mermaid_core/src/diagrams/git/git_graph.dart';
import 'package:mermaid_core/src/ir/scene_utils.dart' show sceneNodeBounds;
import 'package:test/test.dart';

const _mermaid = Mermaid(measurer: ApproximateTextMeasurer());

Point _commitCenter(RenderScene scene, String id) {
  final group = scene.nodes.whereType<SceneGroup>().singleWhere(
    (node) => node.id == 'commit_$id',
  );
  return group.children
      .whereType<SceneShape>()
      .map((shape) => shape.geometry)
      .whereType<CircleGeometry>()
      .first
      .center;
}

void main() {
  const body = '''
commit id: "first" tag: "v1"
branch feature
checkout feature
commit id: "feature"
checkout main
commit id: "main-next"
merge feature id: "merged"
''';

  test('parser preserves RL as a distinct direction', () {
    expect(
      parseGitGraph('gitGraph RL\ncommit').direction,
      GitDirection.rightLeft,
    );
    expect(
      parseGitGraph('gitGraph LR\ncommit').direction,
      GitDirection.leftRight,
    );
  });

  test('RL reverses commits, labels, tags, branches, and merge routes', () {
    final lr = _mermaid.render('gitGraph LR\n$body');
    final rl = _mermaid.render('gitGraph RL\n$body');

    expect(
      _commitCenter(lr, 'first').x,
      lessThan(_commitCenter(lr, 'merged').x),
    );
    expect(
      _commitCenter(rl, 'first').x,
      greaterThan(_commitCenter(rl, 'merged').x),
    );

    final rlBounds = sceneBounds(rl.nodes)!;
    for (final node in rl.nodes) {
      final bounds = sceneNodeBounds(node);
      if (bounds == null) continue;
      expect(bounds.left, greaterThanOrEqualTo(rlBounds.left - 0.01));
      expect(bounds.right, lessThanOrEqualTo(rlBounds.right + 0.01));
    }

    final first = rl.nodes.whereType<SceneGroup>().singleWhere(
      (node) => node.id == 'commit_first',
    );
    final tag = first.children
        .whereType<SceneShape>()
        .map((shape) => shape.geometry)
        .whereType<PolygonGeometry>()
        .firstWhere((polygon) => polygon.points.length == 6);
    expect(tag.points.first.x, greaterThan(tag.points.skip(2).first.x));

    final label = first.children.whereType<SceneText>().singleWhere(
      (text) => text.text == 'first',
    );
    expect(label.rotation, 45);

    expect(renderSceneToSvg(rl), isNot(renderSceneToSvg(lr)));
  });
}
