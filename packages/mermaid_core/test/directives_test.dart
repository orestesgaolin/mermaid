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
