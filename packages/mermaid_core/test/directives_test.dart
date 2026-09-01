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

  test('default color scales match Mermaid 11', () {
    const theme = MermaidTheme.defaultTheme;

    expect(
      [
        theme.cScale0,
        theme.cScale1,
        theme.cScale2,
        theme.cScale3,
        theme.cScale4,
        theme.cScale5,
        theme.cScale6,
        theme.cScale7,
        theme.cScale8,
        theme.cScale9,
        theme.cScale10,
        theme.cScale11,
      ],
      const [
        Color(0xff8686ff),
        Color(0xffffff78),
        Color(0xffd7ff86),
        Color(0xffc286ff),
        Color(0xffff86ff),
        Color(0xffff86c2),
        Color(0xffff8686),
        Color(0xffffc286),
        Color(0xffc2ff86),
        Color(0xff86ffc2),
        Color(0xff86ffff),
        Color(0xff86c2ff),
      ],
    );
    expect(theme.cScaleInv2, const Color(0xffd0b9ff));
    expect(theme.cScalePeer0, const Color(0xff3939ff));
    expect(theme.cScalePeer11, const Color(0xff399cff));
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
