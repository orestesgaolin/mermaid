import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/render/svg_renderer.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

List<SceneNode> _flatten(List<SceneNode> nodes) => [
  for (final node in nodes) ...[
    node,
    if (node is SceneGroup) ..._flatten(node.children),
  ],
];

void main() {
  test('journey labels contrast with their boxes in scene and SVG', () {
    const source = '''
journey
    title My working day
    section Go to work
      Make tea: 5: Me
      Do work: 1: Me, Cat
    section Go home
      Sit down: 5: Me
''';
    final scene = const Mermaid(
      measurer: ApproximateTextMeasurer(),
    ).render(source);

    SceneGroup group(String id) => _flatten(
      scene.nodes,
    ).whereType<SceneGroup>().singleWhere((node) => node.id == id);

    for (final labelGroup in [
      group('section_0'),
      group('task_Make tea'),
      group('section_1'),
      group('task_Sit down'),
    ]) {
      final boxColor = labelGroup.children
          .whereType<SceneShape>()
          .where((shape) => shape.geometry is RectGeometry)
          .single
          .fill!
          .color;
      final labelColor = labelGroup.children
          .whereType<SceneText>()
          .single
          .color;
      expect(labelColor, MermaidTheme.defaultTheme.textColor);
      expect(labelColor, isNot(boxColor));
    }

    final svg = renderSceneToSvg(scene);
    expect(
      svg,
      matches(
        RegExp(r'<text[^>]+fill="#333333"><tspan[^>]+>Go to work</tspan>'),
      ),
    );
    expect(
      svg,
      matches(RegExp(r'<text[^>]+fill="#333333"><tspan[^>]+>Make tea</tspan>')),
    );

    const customText = Color(0xff123456);
    final customScene = Mermaid(
      measurer: const ApproximateTextMeasurer(),
      theme: MermaidTheme.defaultTheme.copyWith(textColor: customText),
    ).render(source);
    final labelTexts = _flatten(customScene.nodes)
        .whereType<SceneGroup>()
        .where((node) =>
            node.id?.startsWith('section_') == true ||
            node.id?.startsWith('task_') == true)
        .expand((node) => node.children.whereType<SceneText>());
    expect(labelTexts, isNotEmpty);
    expect(labelTexts.every((text) => text.color == customText), isTrue);
  });
}
