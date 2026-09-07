import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

import 'support/scene.dart';

void main() {
  const source = '''
requirementDiagram
  requirement r1:::important {
    id: 1
    text: Styled requirement
    risk: high
    verifymethod: test
  }
  element e1 {
    type: simulation
  }
  classDef default fill:#eeeeee,stroke:#222222,color:#333333
  classDef important fill:#ffeecc,stroke:#0066cc,stroke-width:4px,font-weight:bold
  class e1 important
  style r1 fill:rgb(255, 0, 0),color:#123456
  link r1 "https://example.test/requirements/1" "Open requirement"
  callback e1 "selectElement" "Select element"
  e1 - satisfies -> r1
''';

  test('class and inline styles change requirement scene paint', () {
    final diagram = parseRequirementDiagram(source);
    expect(diagram.nodes['r1']!.classes, ['important']);
    expect(diagram.nodes['e1']!.classes, ['important']);
    expect(diagram.nodes['r1']!.styles['fill'], 'rgb(255, 0, 0)');

    final scene = const Mermaid(
      measurer: ApproximateTextMeasurer(),
    ).render(source);
    final r1 = groupsOf(scene.nodes).singleWhere((node) => node.id == 'r1');
    final box = shapesOf(
      r1.children,
    ).firstWhere((shape) => shape.geometry is RectGeometry);
    final labels = textsOf(r1.children).toList();

    expect(box.fill?.color, const Color(0xffff0000));
    expect(box.stroke?.color, const Color(0xff0066cc));
    expect(box.stroke?.width, 4);
    expect(
      labels.every((label) => label.color == const Color(0xff123456)),
      isTrue,
    );
    expect(labels.every((label) => label.style.fontWeight == 700), isTrue);
  });

  test('links, tooltips, and callback names remain available to Dart', () {
    final diagram = parseRequirementDiagram(source);
    expect(diagram.nodes['r1']!.link, 'https://example.test/requirements/1');
    expect(diagram.nodes['r1']!.tooltip, 'Open requirement');
    expect(diagram.nodes['e1']!.callback, 'selectElement');
    expect(diagram.nodes['e1']!.tooltip, 'Select element');

    final scene = const Mermaid(
      measurer: ApproximateTextMeasurer(),
    ).render(source);
    final r1 = groupsOf(scene.nodes).singleWhere((node) => node.id == 'r1');
    final e1 = groupsOf(scene.nodes).singleWhere((node) => node.id == 'e1');
    expect(r1.link, 'https://example.test/requirements/1');
    expect(r1.tooltip, 'Open requirement');
    expect(e1.link, isNull);
    expect(e1.tooltip, 'Select element');

    final svg = renderSceneToSvg(scene);
    expect(svg, contains('<a href="https://example.test/requirements/1"'));
    expect(svg, contains('<title>Open requirement</title>'));
    expect(svg, contains('fill="#ff0000"'));
  });
}
