import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
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
  testWidgets('controller focuses a real node at the viewport center', (
    tester,
  ) async {
    const source = 'graph LR\nA[Start]-->B[Current step]-->C[Finish]';
    final controller = MermaidViewController();
    String? tappedNode;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        MermaidView(
          source: source,
          controller: controller,
          onNodeTap: (id, _) => tappedNode = id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final focus = controller.focusNode('B', zoom: 1.5, animate: false);
    await tester.pump();
    await tester.pump();
    expect(await focus, isTrue);

    final scene = core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(source);
    final nodeCenter = scene.boundsOfNode('B')!.center;
    final viewportPoint = MatrixUtils.transformPoint(
      controller.transformation,
      Offset(nodeCenter.x, nodeCenter.y),
    );
    expect(viewportPoint.dx, closeTo(300, 1e-6));
    expect(viewportPoint.dy, closeTo(200, 1e-6));
    expect(controller.transformation.getMaxScaleOnAxis(), closeTo(1.5, 1e-9));
    await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
    expect(tappedNode, 'B');
  });

  testWidgets('controller uses new source bounds and defines no-op results', (
    tester,
  ) async {
    final detached = MermaidViewController();
    addTearDown(detached.dispose);
    expect(await detached.focusNode('A'), isFalse);
    expect(await detached.fitAll(), isFalse);

    final controller = MermaidViewController();
    addTearDown(controller.dispose);
    var source = 'graph LR\nA-->B';
    late StateSetter updateSource;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateSource = setState;
              return SizedBox(
                width: 600,
                height: 400,
                child: MermaidView(source: source, controller: controller),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      await _runControllerCommand(tester, controller.focusNode('missing')),
      isFalse,
    );
    expect(await controller.focusNode('A', zoom: double.nan), isFalse);
    updateSource(() => source = 'graph LR\nA-->B-->C[New current step]');
    final focus = controller.focusNode('C', animate: false);
    await tester.pump();
    await tester.pump();
    expect(await focus, isTrue);

    final scene = core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(source);
    final center = scene.boundsOfNode('C')!.center;
    final viewportPoint = MatrixUtils.transformPoint(
      controller.transformation,
      Offset(center.x, center.y),
    );
    expect(viewportPoint, const Offset(300, 200));

    updateSource(() => source = 'graph TD\nthis is not valid mermaid');
    final staleFocus = controller.focusNode('C', animate: false);
    await tester.pump();
    await tester.pump();
    expect(await staleFocus, isFalse);
  });

  testWidgets(
    'controller animation and built-in controls share one transform',
    (tester) async {
      final controller = MermaidViewController();
      var notifications = 0;
      controller.addListener(() => notifications++);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(MermaidView(source: 'graph TD\nA-->B', controller: controller)),
      );
      await tester.pumpAndSettle();

      final beforeButton = controller.transformation;
      final notificationsBeforeButton = notifications;
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(
        controller.transformation.getMaxScaleOnAxis(),
        greaterThan(beforeButton.getMaxScaleOnAxis()),
      );
      expect(controller.transformation, equals(_transform(tester)));
      expect(notifications, greaterThan(notificationsBeforeButton));

      final fit = controller.fitAll(animate: true);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      expect(controller.transformation, isNot(equals(beforeButton)));
      await tester.pumpAndSettle();
      expect(await fit, isTrue);
      final fitted = controller.transformation;

      await tester.tap(find.byIcon(Icons.keyboard_arrow_left));
      await tester.pump();
      expect(controller.transformation, isNot(equals(fitted)));
      await tester.tap(find.byIcon(Icons.center_focus_strong));
      await tester.pump();
      expect(controller.transformation, equals(fitted));
    },
  );

  testWidgets('controller swap cancels a pending command and permits reuse', (
    tester,
  ) async {
    final first = MermaidViewController();
    final second = MermaidViewController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    var controller = first;
    late StateSetter swap;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              swap = setState;
              return SizedBox(
                width: 600,
                height: 400,
                child: MermaidView(
                  source: 'graph LR\nA-->B',
                  controller: controller,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pending = first.focusNode('B', animate: false);
    swap(() => controller = second);
    await tester.pump();
    await tester.pump();
    expect(await pending, isFalse);
    expect(first.isAttached, isFalse);
    expect(second.isAttached, isTrue);
    expect(
      await _runControllerCommand(
        tester,
        second.focusNode('B', animate: false),
      ),
      isTrue,
    );

    swap(() => controller = first);
    await tester.pump();
    expect(first.isAttached, isTrue);
    expect(second.isAttached, isFalse);
  });

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

  testWidgets('fullscreen popup fits and zooms with the options it was given', (
    tester,
  ) async {
    const padding = 60.0;
    const zoomStep = 2.0;
    await tester.pumpWidget(
      _host(
        const MermaidView(
          source: 'graph TD\nA-->B',
          padding: padding,
          zoomStep: zoomStep,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    final viewer = find.descendant(
      of: dialog,
      matching: find.byType(InteractiveViewer),
    );
    final transformation = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    final viewport = tester.getSize(viewer);
    final diagram = tester.getSize(
      find.descendant(of: dialog, matching: find.byType(MermaidDiagram)),
    );
    double fitFor(double pad) => math.min(
      (viewport.width - 2 * pad) / diagram.width,
      (viewport.height - 2 * pad) / diagram.height,
    );

    final fitted = transformation.value.getMaxScaleOnAxis();
    expect(fitted, closeTo(fitFor(padding), 0.001));
    expect(
      fitted,
      isNot(closeTo(fitFor(20), 0.001)),
      reason: 'the default padding must not be what the popup used',
    );

    await tester.tap(
      find.descendant(of: dialog, matching: find.byIcon(Icons.add)),
    );
    await tester.pump();
    expect(
      transformation.value.getMaxScaleOnAxis(),
      closeTo(fitted * zoomStep, 0.001),
    );
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

Future<bool> _runControllerCommand(
  WidgetTester tester,
  Future<bool> command,
) async {
  await tester.pump();
  await tester.pump();
  return command;
}
