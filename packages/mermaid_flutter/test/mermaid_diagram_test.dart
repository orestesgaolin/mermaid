import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  testWidgets('node bounds center targets the matching diagram node', (
    tester,
  ) async {
    const source = 'flowchart TD\n  n1["First"] -->|next| n2["Second"]';
    final scene = core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(source);
    String? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MermaidDiagram(
              source: source,
              onNodeTap: (id, link) => tapped = id,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final origin = tester.getTopLeft(find.byType(MermaidDiagram));
    final center = scene.boundsOfNode('n1')!.center;
    await tester.tapAt(origin + Offset(center.x, center.y));
    await tester.pump();

    expect(tapped, 'n1');
  });
}
