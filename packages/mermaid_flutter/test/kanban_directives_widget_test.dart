import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

import 'support/harness.dart';

void main() {
  testWidgets('Kanban click metadata drives semantics and Dart tap callback', (
    tester,
  ) async {
    const source = '''
kanban
  todo[To Do]
    task[Ship release]
  click task href "https://example.test/tasks/1" "Open task"
''';
    final taps = <(String, String?)>[];

    await pumpDiagram(
      tester,
      MermaidDiagram(
        source: source,
        semanticNodes: true,
        onNodeTap: (id, link) => taps.add((id, link)),
      ),
    );
    await tester.pump();

    final target = find.semantics.byLabel('Ship release');
    expect(target, findsOneWidget);
    final semantics = target.evaluate().single.getSemanticsData();
    expect(semantics.identifier, 'task');
    expect(semantics.label, 'Ship release');
    expect(semantics.tooltip, 'Open task');
    expect(semantics.hasAction(ui.SemanticsAction.tap), isTrue);

    tester.semantics.tap(target);
    await tester.pump();
    expect(taps, [('task', 'https://example.test/tasks/1')]);
  });
}
