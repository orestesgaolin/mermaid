import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:website/flutter/material_theme_demo.dart';

void main() {
  testWidgets('Material theme control recolors the embedded Mermaid view', (
    tester,
  ) async {
    var fullscreenRequested = false;
    await tester.pumpWidget(
      MaterialThemeDemo(
        source: 'flowchart LR\n  A --> B',
        onRequestFullscreen: () => fullscreenRequested = true,
      ),
    );

    final lightView = tester.widget<MermaidView>(find.byType(MermaidView));
    final lightBackground = lightView.theme.background;
    expect(lightBackground.value, Colors.white.toARGB32());
    expect(lightView.theme.primaryColor.value, 0xffd7e3ff);
    expect(find.byTooltip('Use dark Material theme'), findsOneWidget);
    lightView.onRequestFullscreen!();
    expect(fullscreenRequested, isTrue);

    await tester.tap(find.byKey(const ValueKey('material-theme-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('Use light Material theme'), findsOneWidget);
    final darkView = tester.widget<MermaidView>(find.byType(MermaidView));
    expect(darkView.theme.background, isNot(lightBackground));
    expect(darkView.theme.background.value, const Color(0xff101214).toARGB32());
    expect(darkView.theme.primaryColor.value, 0xff174a7e);
  });
}
