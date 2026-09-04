/// Tests for the gitGraph diagram.
library;

import 'package:mermaid_core/src/detect.dart';
import 'package:mermaid_core/src/diagrams/git/git_graph.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

void main() {
  group('detect', () {
    test('recognizes gitGraph header', () {
      expect(detectDiagramType('gitGraph\n  commit'), DiagramType.gitGraph);
      expect(detectDiagramType('gitGraph LR:\n  commit'), DiagramType.gitGraph);
    });
  });

  group('parse', () {
    test('commits go to the current branch and chain to parents', () {
      final g = parseGitGraph('''
gitGraph
   commit
   commit
   branch develop
   checkout develop
   commit
   checkout main
   merge develop
''');
      expect(g.branchOrder, ['main', 'develop']);
      // 3 commits + 1 merge.
      expect(g.commits.length, 4);
      final develop = g.commits.where((c) => c.branch == 'develop').toList();
      expect(develop.length, 1);
      // Develop's first commit branches off main's second commit.
      expect(develop.single.parents.single, g.commits[1].id);
      final merge = g.commits.last;
      expect(merge.isMerge, isTrue);
      expect(merge.branch, 'main');
      // Merge has two parents: main tip + develop tip.
      expect(merge.parents.length, 2);
      expect(merge.parents.last, develop.single.id);
    });

    test('commit attributes: id, type, tag', () {
      final g = parseGitGraph('''
gitGraph
   commit id: "A" tag: "v1" type: HIGHLIGHT
   commit type: REVERSE
''');
      expect(g.commits.first.id, 'A');
      expect(g.commits.first.tag, 'v1');
      expect(g.commits.first.type, GitCommitType.highlight);
      expect(g.commits[1].type, GitCommitType.reverse);
    });

    test('switch is an alias for checkout', () {
      final g = parseGitGraph('''
gitGraph
   commit
   branch dev
   switch main
   commit
''');
      // Both main commits land on main.
      expect(g.commits.where((c) => c.branch == 'main').length, 2);
    });

    test('TB direction parsed', () {
      final g = parseGitGraph('gitGraph TB:\n  commit');
      expect(g.direction, GitDirection.topBottom);
    });

    test('unknown checkout target throws', () {
      expect(
        () => parseGitGraph('gitGraph\n  checkout nope'),
        throwsA(isA<MermaidParseException>()),
      );
    });
  });

  group('layout', () {
    test('produces a commit node and a branch label per branch', () {
      final scene = layoutGitGraph(
        parseGitGraph('''
gitGraph
   commit id: "first"
   branch develop
   checkout develop
   commit
'''),
        measurer: measurer,
        theme: theme,
      );
      final groups = scene.nodes.whereType<SceneGroup>().toList();
      expect(groups.any((g) => g.id == 'commit_first'), isTrue);
      // Branch labels for main and develop are emitted as text.
      List<SceneNode> flat(List<SceneNode> n) => [
        for (final x in n) ...[x, if (x is SceneGroup) ...flat(x.children)],
      ];
      final texts = flat(
        scene.nodes,
      ).whereType<SceneText>().map((t) => t.text).toSet();
      expect(texts.containsAll({'main', 'develop', 'first'}), isTrue);
    });

    test('rotates commit label backgrounds', () {
      final scene = layoutGitGraph(
        parseGitGraph('''
gitGraph
   commit id: "Normal" tag: "v1.0.0"
'''),
        measurer: measurer,
        theme: theme,
      );
      final commit = scene.nodes.whereType<SceneGroup>().singleWhere(
        (group) => group.id == 'commit_Normal',
      );
      final polygons = commit.children
          .whereType<SceneShape>()
          .map((shape) => shape.geometry)
          .whereType<PolygonGeometry>()
          .toList();

      final labelBackground = polygons.singleWhere(
        (polygon) => polygon.points.length == 4,
      );
      expect(labelBackground.points.map((point) => point.x).toSet().length, 4);
      expect(labelBackground.points.map((point) => point.y).toSet().length, 4);
    });

    test('LR tag spear tip points left, outside the tag body', () {
      final scene = layoutGitGraph(
        parseGitGraph('''
gitGraph LR:
   commit id: "Tagged" tag: "v1.0.0"
'''),
        measurer: measurer,
        theme: theme,
      );
      final commit = scene.nodes.whereType<SceneGroup>().singleWhere(
        (group) => group.id == 'commit_Tagged',
      );
      final shapes = commit.children.whereType<SceneShape>().toList();

      // The commit bullet is the largest circle in the group; the tag hole is
      // the small one. Both come straight out of the rendered scene.
      final circles = shapes
          .map((shape) => shape.geometry)
          .whereType<CircleGeometry>()
          .toList();
      final bullet = circles.reduce((a, b) => a.radius >= b.radius ? a : b);
      final hole = circles.reduce((a, b) => a.radius <= b.radius ? a : b);
      expect(hole.radius, lessThan(bullet.radius));

      final tagBody = shapes
          .map((shape) => shape.geometry)
          .whereType<PolygonGeometry>()
          .singleWhere((polygon) => polygon.points.length == 6);
      final tagText = commit.children.whereType<SceneText>().singleWhere(
        (text) => text.text == 'v1.0.0',
      );

      // Polygon order is: notch top, notch bottom, then the four body corners
      // starting at the top-left one.
      final notchX = tagBody.points[0].x;
      expect(tagBody.points[1].x, notchX);
      final bodyLeft = tagBody.points[2].x;
      final bodyRight = tagBody.points[3].x;
      expect(bodyRight, greaterThan(bodyLeft));

      // The spear tip must stick out to the LEFT of the body, with the hole
      // between the tip and the body edge.
      expect(
        notchX,
        lessThan(bodyLeft),
        reason: 'the LR tag notch must sit outside (left of) the body edge',
      );
      expect(hole.center.x, greaterThan(notchX));
      expect(hole.center.x, lessThan(bodyLeft));
      expect(hole.center.y, closeTo(tagText.bounds.center.y, 0.001));

      // Upstream (gitGraphRenderer.drawCommitTags) draws the notch and hole
      // from `pos` and the body from `pos + LAYOUT_OFFSET`, which is the
      // commit centre: notch = cx - w/2 - 12, hole = cx - w/2 - 8,
      // body = cx - w/2 - 4.
      final cx = bullet.center.x;
      final halfWidth = tagText.bounds.width / 2;
      expect(notchX, closeTo(cx - halfWidth - 12, 0.001));
      expect(hole.center.x, closeTo(cx - halfWidth - 8, 0.001));
      expect(bodyLeft, closeTo(cx - halfWidth - 4, 0.001));
      expect(bodyRight, closeTo(cx + halfWidth + 4, 0.001));
    });
  });
}
