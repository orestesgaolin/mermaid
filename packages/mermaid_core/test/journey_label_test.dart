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

    // Section bands take the diagram's title colour; task boxes take the body
    // text colour. Both must differ from the fill they sit on.
    final expectedColors = {
      'section_0': MermaidTheme.defaultTheme.titleColor,
      'section_1': MermaidTheme.defaultTheme.titleColor,
      'task_Make tea': MermaidTheme.defaultTheme.textColor,
      'task_Sit down': MermaidTheme.defaultTheme.textColor,
    };
    expectedColors.forEach((id, expectedColor) {
      final labelGroup = group(id);
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
      expect(labelColor, expectedColor, reason: id);
      expect(labelColor, isNot(boxColor), reason: id);
    });

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
    const customTitle = Color(0xff654321);
    final customScene = Mermaid(
      measurer: const ApproximateTextMeasurer(),
      theme: MermaidTheme.defaultTheme.copyWith(
        textColor: customText,
        titleColor: customTitle,
      ),
    ).render(source);
    Iterable<SceneText> labelsWithPrefix(String prefix) =>
        _flatten(customScene.nodes)
            .whereType<SceneGroup>()
            .where((node) => node.id?.startsWith(prefix) == true)
            .expand((node) => node.children.whereType<SceneText>());

    final sectionTexts = labelsWithPrefix('section_');
    final taskTexts = labelsWithPrefix('task_');
    expect(sectionTexts, isNotEmpty);
    expect(taskTexts, isNotEmpty);
    expect(sectionTexts.every((text) => text.color == customTitle), isTrue);
    expect(taskTexts.every((text) => text.color == customText), isTrue);
  });
}
