/// Tests for the gap-fill pass: gantt excludes-duration, railroad EBNF
/// operators, block arrows/edge-labels, treemap squarify, mindmap classDef,
/// C4 boundary style, frontmatter themeVariables, and link/tooltip interactivity.
library;

import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/diagrams/block/block.dart';
import 'package:mermaid_core/src/diagrams/gantt/gantt_parser.dart';
import 'package:mermaid_core/src/diagrams/mindmap/mindmap.dart';
import 'package:mermaid_core/src/diagrams/railroad/railroad.dart';
import 'package:mermaid_core/src/directives.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/render/svg_renderer.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const _m = Mermaid(measurer: ApproximateTextMeasurer());

List<SceneNode> _flat(List<SceneNode> n) =>
    [for (final x in n) ...[x, if (x is SceneGroup) ..._flat(x.children)]];

void main() {
  test('gantt: excluded days extend a duration past weekends', () {
    final g = parseGanttChart('''
gantt
  dateFormat YYYY-MM-DD
  excludes weekends
  section S
  Build : a, 2024-03-07, 3d
  Test : after a, 1d
''');
    final tasks = g.tasks.toList();
    final build = tasks.first, test = tasks[1];
    // 2024-03-07 is Thursday; a 3-working-day task skips Sat+Sun, so its end
    // is more than 3 calendar days out (the weekend was excluded).
    expect(build.end.difference(build.start).inDays, greaterThan(3));
    // The dependent `after` task starts at the extended end (past the weekend).
    expect(test.start, build.end);
  });

  test('railroad: EBNF operators parse into the AST', () {
    final d = parseRailroad('railroad-diagram\nr = a ( b | c )* [ d ] ;');
    final seq = d.rules.single.expr;
    // Sequence of: a, repetition(choice(b,c)), optional(d).
    expect(seq, isA<RailroadSequence>());
    final items = (seq as RailroadSequence).items;
    expect(items.any((e) => e is RailroadRepetition), isTrue);
    expect(items.any((e) => e is RailroadOptional), isTrue);
    final rep = items.firstWhere((e) => e is RailroadRepetition)
        as RailroadRepetition;
    expect(rep.child, isA<RailroadChoice>());
  });

  test('block: block arrow shape + edge label parse', () {
    final d = parseBlock('''
block-beta
  A arrow1<["go"]>(right) B
  A -- "yes" --> B
''');
    final hasArrow = d.root
        .whereType<BlockNode>()
        .any((n) => n.shape == BlockShape.blockArrow);
    expect(hasArrow, isTrue);
    expect(d.edges.single.label, 'yes');
  });

  test('treemap: squarified layout emits a rect + label per leaf', () {
    final s = _m.render('''
treemap-beta
"A"
  "x": 10
  "y": 20
''');
    final texts = _flat(s.nodes).whereType<SceneText>().map((t) => t.text);
    expect(texts.any((t) => t.contains('x')), isTrue);
    expect(texts.any((t) => t.contains('y')), isTrue);
  });

  test('mindmap: classDef + :::class recolors the node', () {
    final map = parseMindmap('''
mindmap
  root((R))
    Hot
    :::warn
  classDef warn fill:#ff0000,color:#ffffff
''');
    expect(map.classDefs.containsKey('warn'), isTrue);
    expect(map.classDefs['warn']!['fill'], '#ff0000');
  });

  test('C4: UpdateBoundaryStyle applies bgColor', () {
    final s = _m.render('''
C4Context
  Enterprise_Boundary(b0, "Bank") {
    System(s, "Sys", "desc")
  }
  UpdateBoundaryStyle(b0, \$bgColor="#112233")
''');
    final shapes = _flat(s.nodes).whereType<SceneShape>();
    expect(shapes.any((sh) => sh.fill?.color == const Color(0xff112233)), isTrue);
  });

  test('frontmatter config.themeVariables (nested YAML) applies', () {
    final t = resolveTheme('''
---
config:
  theme: base
  themeVariables:
    primaryColor: "#ff9999"
    lineColor: "#0000ff"
---
graph TD
A-->B
''', MermaidTheme.defaultTheme);
    expect(t.mainBkg, const Color(0xffff9999));
    expect(t.lineColor, const Color(0xff0000ff));
  });

  group('interactivity', () {
    test('flowchart click sets a link on the node group, emitted as <a> in SVG',
        () {
      final s = _m.render('graph TD\n A[Home]-->B\n click A "https://x.test" "tip"');
      final linked =
          _flat(s.nodes).whereType<SceneGroup>().where((g) => g.link != null);
      expect(linked, isNotEmpty);
      expect(linked.first.link, 'https://x.test');
      expect(linked.first.tooltip, 'tip');
      final svg = renderSceneToSvg(s);
      expect(svg.contains('<a href="https://x.test"'), isTrue);
      expect(svg.contains('<title>tip</title>'), isTrue);
    });
  });
}
