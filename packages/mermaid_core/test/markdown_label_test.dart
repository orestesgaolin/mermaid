import 'package:mermaid_core/src/diagrams/flowchart/markdown_label.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/render/svg_renderer.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/text/text_style.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

void main() {
  test('renders strong emphasis without Markdown delimiters', () {
    const style = TextStyleSpec(fontFamily: 'sans-serif', fontSize: 16);
    final label = layoutMarkdownLabel(
      'As an **App developer**',
      style,
      const ApproximateTextMeasurer(),
    );

    expect(label.plainText, 'As an App developer');
    expect(label.runs.map((run) => run.text), ['As an ', 'App developer']);
    expect(label.runs[0].style.fontWeight, 400);
    expect(label.runs[1].style.fontWeight, 700);

    final sceneNodes = label.render(
      const Point(100, 50),
      MermaidTheme.defaultTheme.textColor,
    );
    final textNodes = sceneNodes.cast<SceneText>().toList();
    expect(textNodes.map((node) => node.text), ['As an ', 'App developer']);
    expect(
      textNodes.last.bounds.left,
      closeTo(textNodes.first.bounds.right, 0.001),
    );

    final svg = renderSceneToSvg(
      RenderScene(size: const Size(200, 100), nodes: sceneNodes),
    );
    expect(svg, contains('font-weight="700"'));
    expect(svg, isNot(contains('**')));
  });
}
