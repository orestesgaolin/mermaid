import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:website/flutter/material_theme_demo.dart';

void main() {
  testWidgets('uses native Mermaid themes until Material bridge is enabled', (
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
    expect(lightView.theme, core.MermaidTheme.defaultTheme);
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('material-theme-toggle')),
          )
          .selected,
      isFalse,
    );
    expect(find.byTooltip('Use dark theme'), findsOneWidget);
    expect(find.byTooltip('Use Material theme bridge'), findsOneWidget);
    lightView.onRequestFullscreen!();
    expect(fullscreenRequested, isTrue);

    await tester.tap(find.byKey(const ValueKey('brightness-theme-toggle')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Use light theme'), findsOneWidget);
    expect(
      tester.widget<MermaidView>(find.byType(MermaidView)).theme,
      core.MermaidTheme.darkTheme,
    );

    await tester.tap(find.byKey(const ValueKey('material-theme-toggle')));
    await tester.pumpAndSettle();

    final materialDarkView = tester.widget<MermaidView>(
      find.byType(MermaidView),
    );
    expect(materialDarkView.theme, isNot(core.MermaidTheme.darkTheme));
    expect(
      materialDarkView.theme.background.value,
      const Color(0xff101214).toARGB32(),
    );
    expect(materialDarkView.theme.primaryColor.value, 0xff174a7e);
    expect(find.byTooltip('Use native Mermaid theme'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('material-theme-toggle')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MermaidView>(find.byType(MermaidView)).theme,
      core.MermaidTheme.darkTheme,
    );
    expect(find.byTooltip('Use Material theme bridge'), findsOneWidget);
  });
}
