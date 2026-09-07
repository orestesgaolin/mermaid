import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed, top-left viewport keeps scene-to-screen coordinates consistent.
Widget mermaidViewHost(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 600, height: 400, child: child),
    ),
  ),
);

Widget diagramHost(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

Future<void> pumpMermaidView(WidgetTester tester, Widget child) =>
    tester.pumpWidget(mermaidViewHost(child));

Future<void> pumpDiagram(WidgetTester tester, Widget child) =>
    tester.pumpWidget(diagramHost(child));
