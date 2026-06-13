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
      expect(detectDiagramType('gitGraph LR:\n  commit'),
          DiagramType.gitGraph);
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
      expect(() => parseGitGraph('gitGraph\n  checkout nope'),
          throwsA(isA<MermaidParseException>()));
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
            for (final x in n) ...[
              x,
              if (x is SceneGroup) ...flat(x.children),
            ],
          ];
      final texts =
          flat(scene.nodes).whereType<SceneText>().map((t) => t.text).toSet();
      expect(texts.containsAll({'main', 'develop', 'first'}), isTrue);
    });
  });
}
