import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

// Issue #79: `<b>` in a flowchart label is painted bold, not as tag text.
const _source = '''
flowchart TD
    E["<b>Endpoint</b><br/>Receives external requests<br/>Knows about: Service"]
    S["<b>Service / Use Case</b><br/>Knows about: Repository (interface)"]
    E --> S
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bold run is measured with the Flutter text engine and fits the box',
    () {
      const measurer = FlutterTextMeasurer();
      final scene = core.Mermaid(measurer: measurer).render(_source);
      for (final id in ['E', 'S']) {
        final group = _findGroup(scene.nodes, id);
        final texts = _texts(group);
        expect(texts.map((t) => t.text).join(), isNot(contains('<')));
        final bold = texts.first;
        expect(bold.style.fontWeight, 700);
        expect(
          bold.bounds.width,
          measurer.measure(bold.text, bold.style).width,
        );
        final box = group.children
            .whereType<core.SceneShape>()
            .map((s) => s.geometry)
            .whereType<core.RectGeometry>()
            .first
            .rect;
        for (final t in texts) {
          expect(t.bounds.left, greaterThanOrEqualTo(box.left), reason: t.text);
          expect(t.bounds.right, lessThanOrEqualTo(box.right), reason: t.text);
          expect(t.bounds.top, greaterThanOrEqualTo(box.top), reason: t.text);
          expect(
            t.bounds.bottom,
            lessThanOrEqualTo(box.bottom),
            reason: t.text,
          );
        }
      }
    },
  );

  testWidgets('semantic node label has the text without tags', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MermaidDiagram(source: _source, semanticNodes: true),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel(
        'Endpoint\nReceives external requests\nKnows about: Service',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('<b>')), findsNothing);
    expect(tester.takeException(), isNull);
  }, semanticsEnabled: true);
}

core.SceneGroup _findGroup(List<core.SceneNode> nodes, String id) {
  for (final node in nodes) {
    if (node is! core.SceneGroup) continue;
    if (node.id == id) return node;
    try {
      return _findGroup(node.children, id);
    } on StateError {
      continue;
    }
  }
  throw StateError('no group $id');
}

List<core.SceneText> _texts(core.SceneNode node) => switch (node) {
  core.SceneText() => [node],
  core.SceneGroup(:final children) => [for (final c in children) ..._texts(c)],
  _ => const [],
};
