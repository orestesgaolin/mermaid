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

Matrix4 _transform(WidgetTester tester) {
  final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
  return iv.transformationController!.value.clone();
}

void main() {
  testWidgets('renders the diagram with interactive controls', (tester) async {
    await tester.pumpWidget(
      _host(const MermaidView(source: 'graph TD\nA-->B')),
    );
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
    await tester.pumpWidget(
      _host(const MermaidView(source: 'graph TD\nA-->B')),
    );
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

  testWidgets('arrow controls move the view in their labelled direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const MermaidView(source: 'graph TD\nA-->B')),
    );
    await tester.pumpAndSettle();

    final fitted = _transform(tester).getTranslation();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pump();
    expect(_transform(tester).getTranslation().y, greaterThan(fitted.y));

    await tester.tap(find.byIcon(Icons.center_focus_strong));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_left));
    await tester.pump();
    expect(_transform(tester).getTranslation().x, greaterThan(fitted.x));

    await tester.tap(find.byIcon(Icons.center_focus_strong));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
    await tester.pump();
    expect(_transform(tester).getTranslation().x, lessThan(fitted.x));

    await tester.tap(find.byIcon(Icons.center_focus_strong));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pump();
    expect(_transform(tester).getTranslation().y, lessThan(fitted.y));
  });

  testWidgets('viewport resize re-fits after the user moved the diagram', (
    tester,
  ) async {
    var size = const Size(600, 400);
    late StateSetter resize;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              resize = setState;
              return SizedBox(
                width: size.width,
                height: size.height,
                child: const MermaidView(source: 'graph TD\nA-->B'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.keyboard_arrow_left));
    await tester.pump();
    resize(() => size = const Size(500, 300));
    await tester.pumpAndSettle();

    final afterResize = _transform(tester);
    await tester.tap(find.byIcon(Icons.center_focus_strong));
    await tester.pump();
    expect(_transform(tester), equals(afterResize));
  });

  testWidgets('fullscreen popup opens a second viewer', (tester) async {
    await tester.pumpWidget(
      _host(const MermaidView(source: 'graph TD\nA-->B')),
    );
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
      _host(const MermaidView(source: 'graph TD\nA-->B', showControls: false)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
}
