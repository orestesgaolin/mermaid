import 'support/scene.dart';
import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

void main() {
  test('frontmatter flow collections match init collection values', () {
    const frontmatter = '''
---
config:
  journey:
    actorColours: ['#ff0000', "#00ff00"]
    sectionFills: [rebeccapurple, '#abcdef']
    sectionColours: ['#123456']
    nested: {palette: ['#010203', '#040506'], flags: {enabled: true}}
---
journey
  section Work
    Task: 5: Dev
''';
    const init = '''
%%{init: {"journey": {"actorColours": ["#ff0000", "#00ff00"], "sectionFills": ["rebeccapurple", "#abcdef"], "sectionColours": ["#123456"], "nested": {"palette": ["#010203", "#040506"], "flags": {"enabled": true}}}}}%%
journey
  section Work
    Task: 5: Dev
''';

    expect(
      resolveDiagramConfig(frontmatter, 'journey'),
      resolveDiagramConfig(init, 'journey'),
    );

    final frontmatterConfig = JourneyConfig.fromSource(frontmatter);
    final initConfig = JourneyConfig.fromSource(init);
    expect(frontmatterConfig.actorColours, initConfig.actorColours);
    expect(frontmatterConfig.sectionFills, initConfig.sectionFills);
    expect(frontmatterConfig.sectionColours, initConfig.sectionColours);

    const renderer = Mermaid(measurer: ApproximateTextMeasurer());
    final frontmatterScene = renderer.render(frontmatter);
    final initScene = renderer.render(init);
    expect(_paintSignature(frontmatterScene), _paintSignature(initScene));
  });
}

List<Object?> _paintSignature(RenderScene scene) => [
  scene.background,
  for (final node in flattenScene(scene.nodes))
    switch (node) {
      SceneShape(:final fill, :final stroke) => (fill?.color, stroke?.color),
      SceneText(:final color) => color,
      _ => null,
    },
];
