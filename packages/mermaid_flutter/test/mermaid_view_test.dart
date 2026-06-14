import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 600, height: 400, child: child)),
      ),
    );

double _scale(WidgetTester tester) {
  final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
  return iv.transformationController!.value.getMaxScaleOnAxis();
}

void main() {
  testWidgets('renders the diagram with interactive controls', (tester) async {
    await tester.pumpWidget(_host(const MermaidView(source: 'graph TD\nA-->B')));
    await tester.pumpAndSettle();

    expect(find.byType(MermaidDiagram), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    // The control cluster: zoom, reset, pan arrows, lock toggle, popup.
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.byIcon(Icons.center_focus_strong), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full), findsOneWidget);
  });

  testWidgets('zoom in increases scale, zoom out decreases it', (tester) async {
    await tester.pumpWidget(_host(const MermaidView(source: 'graph TD\nA-->B')));
    await tester.pumpAndSettle();

    final fitted = _scale(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    final zoomedIn = _scale(tester);
    expect(zoomedIn, greaterThan(fitted));

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(_scale(tester), lessThan(zoomedIn));
  });

  testWidgets('fullscreen popup opens a second viewer', (tester) async {
    await tester.pumpWidget(_host(const MermaidView(source: 'graph TD\nA-->B')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    // The dialog hosts its own viewer (without a nested popup button).
    expect(find.byType(MermaidView), findsNWidgets(2));
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('hides controls when showControls is false', (tester) async {
    await tester.pumpWidget(
        _host(const MermaidView(source: 'graph TD\nA-->B', showControls: false)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
}
