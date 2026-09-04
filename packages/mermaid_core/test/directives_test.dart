/// Theme directive resolution tests.
library;

import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/directives.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

void main() {
  test('init directive selects a named theme', () {
    final t = resolveTheme(
        "%%{init: {'theme': 'dark'}}%%\ngraph TD\nA-->B",
        MermaidTheme.defaultTheme);
    expect(t.mainBkg, MermaidTheme.darkTheme.mainBkg);
  });

  test('forest and neutral are available', () {
    expect(MermaidTheme.named('forest').mainBkg, const Color(0xffcde498));
    expect(MermaidTheme.named('neutral').nodeBorder, const Color(0xff999999));
    expect(MermaidTheme.named('nope').mainBkg, MermaidTheme.defaultTheme.mainBkg);
  });

  test('a theme directive swaps the palette, themeVariables keep it', () {
    final forest = resolveTheme("%%{init: {'theme': 'forest'}}%%\ngraph TD\nA-->B",
        MermaidTheme.defaultTheme);
    expect(forest.cScale0, MermaidTheme.named('forest').cScale0);
    expect(forest.cScale0, isNot(MermaidTheme.defaultTheme.cScale0));

    // themeVariables are applied on top through `copyWith`, which only sets
    // the base fields — the named theme's palettes must survive.
    final tuned = resolveTheme(
        "%%{init: {'theme': 'forest', 'themeVariables': "
        "{'primaryColor': '#ff0000'}}}%%\ngraph TD\nA-->B",
        MermaidTheme.defaultTheme);
    expect(tuned.mainBkg, const Color(0xffff0000));
    expect(tuned.cScale0, forest.cScale0);
    expect(tuned.xyChartPlotColorPalette, forest.xyChartPlotColorPalette);
  });

  test('themeVariables override colors; primaryColor drives mainBkg', () {
    final t = resolveTheme(
        '%%{init: {"theme": "base", "themeVariables": '
        '{"primaryColor": "#ff9999", "lineColor": "#0000ff"}}}%%\n'
        'graph TD\nA-->B',
        MermaidTheme.defaultTheme);
    expect(t.mainBkg, const Color(0xffff9999));
    expect(t.primaryColor, const Color(0xffff9999));
    expect(t.lineColor, const Color(0xff0000ff));
    expect(t.arrowheadColor, const Color(0xff0000ff));
  });

  test('frontmatter config theme', () {
    final t = resolveTheme(
        '---\nconfig:\n  theme: forest\n---\ngraph TD\nA-->B',
        MermaidTheme.defaultTheme);
    expect(t.mainBkg, const Color(0xffcde498));
  });

  test('no directive keeps the base theme', () {
    expect(resolveTheme('graph TD\nA-->B', MermaidTheme.darkTheme).mainBkg,
        MermaidTheme.darkTheme.mainBkg);
  });

  group('frontmatter YAML', () {
    String sankeySource({required String width, String? nodeColors}) => '''
---
config:
  sankey:
    height: 200
    width: $width
${nodeColors ?? ''}---
sankey
A,Bio-conversion,1
''';

    test('an inline comment is not part of the value', () {
      final commented = sankeySource(width: '800 # keep this in sync');
      expect(resolveDiagramConfig(commented, 'sankey')['width'], 800);

      // ...and the diagram is laid out at the same size either way.
      const renderer = Mermaid(measurer: ApproximateTextMeasurer());
      expect(renderer.render(commented).size,
          renderer.render(sankeySource(width: '800')).size);
    });

    test('a quoted value keeps a leading hash', () {
      final config = resolveDiagramConfig('''
---
config:
  sankey:
    linkColor: '#ff0000' # not a comment
---
sankey
A,B,1
''', 'sankey');
      expect(config['linkColor'], '#ff0000');
    });

    test('hyphenated keys reach the diagram config', () {
      final config = resolveDiagramConfig(
        sankeySource(
          width: '400',
          nodeColors: "    nodeColors:\n"
              "      Bio-conversion: '#ff0000'\n"
              "      A: '#00ff00'\n",
        ),
        'sankey',
      );
      expect(config['nodeColors'],
          {'Bio-conversion': '#ff0000', 'A': '#00ff00'});

      // The hyphenated node really gets that colour.
      final scene = const Mermaid(measurer: ApproximateTextMeasurer()).render(
        sankeySource(
          width: '400',
          nodeColors: "    nodeColors:\n"
              "      Bio-conversion: '#ff0000'\n",
        ),
      );
      List<SceneNode> flatten(List<SceneNode> nodes) => [
            for (final n in nodes) ...[
              n,
              if (n is SceneGroup) ...flatten(n.children),
            ],
          ];
      expect(
        flatten(scene.nodes)
            .whereType<SceneShape>()
            .where((s) => s.geometry is RectGeometry)
            .map((s) => s.fill?.color),
        contains(const Color(0xffff0000)),
      );
    });

    test('a flow-style map is read as a nested map', () {
      final config = resolveDiagramConfig('''
---
config:
  sankey:
    nodeColors: {Bio-conversion: '#ff0000', A: '#00ff00'}
    width: 400 # trailing comment
---
sankey
A,Bio-conversion,1
''', 'sankey');
      expect(config['nodeColors'],
          {'Bio-conversion': '#ff0000', 'A': '#00ff00'});
      expect(config['width'], 400);
    });
  });

  test('render applies the directive end to end', () {
    const mermaid = Mermaid(measurer: ApproximateTextMeasurer());
    final scene =
        mermaid.render("%%{init: {'theme': 'forest'}}%%\ngraph TD\nA-->B");
    // Some node is filled with the forest mainBkg.
    bool hasForestFill(List<SceneNode> nodes) => nodes.any((n) => switch (n) {
          SceneGroup(:final children) => hasForestFill(children),
          SceneShape(:final fill) => fill?.color == const Color(0xffcde498),
          _ => false,
        });
    expect(hasForestFill(scene.nodes), isTrue);
  });
}
