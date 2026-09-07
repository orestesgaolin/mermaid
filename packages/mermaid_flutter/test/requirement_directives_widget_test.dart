import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

import 'support/harness.dart';

void main() {
  testWidgets(
    'requirement link and callback directives dispatch through Dart',
    (tester) async {
      const source = '''
requirementDiagram
  requirement r1 {
    id: 1
    text: Linked requirement
  }
  element e1 {
    type: simulation
  }
  link r1 "https://example.test/requirements/1" "Open requirement"
  callback e1 "selectElement" "Select element"
  e1 - satisfies -> r1
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

      final linked = find.semantics.byLabel('r1');
      final callback = find.semantics.byLabel('e1');
      expect(
        linked.evaluate().single.getSemanticsData().tooltip,
        'Open requirement',
      );
      expect(
        callback.evaluate().single.getSemanticsData().tooltip,
        'Select element',
      );

      tester.semantics.tap(linked);
      tester.semantics.tap(callback);
      await tester.pump();
      expect(taps, [
        ('r1', 'https://example.test/requirements/1'),
        ('e1', null),
      ]);
    },
  );
}
