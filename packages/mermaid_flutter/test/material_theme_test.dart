import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in Brightness.values) {
    test('generated palettes stay readable in $brightness', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: brightness,
      );
      final theme = MaterialMermaidTheme.fromColorScheme(scheme);

      for (var lane = 0; lane < theme.git.length; lane++) {
        expect(
          _contrast(theme.git[lane], theme.gitBranchLabel[lane]),
          greaterThanOrEqualTo(4.5),
          reason: 'git lane $lane label is unreadable on its lane color',
        );
        expect(
          _contrast(theme.git[lane], theme.gitInv[lane]),
          greaterThanOrEqualTo(4.5),
          reason: 'git lane $lane inverted color is unreadable on the lane',
        );
      }
      for (var slice = 0; slice < theme.pie.length; slice++) {
        expect(
          _contrast(theme.pie[slice], theme.pieSectionTextColor),
          greaterThanOrEqualTo(4.5),
          reason: 'pie slice ${slice + 1} text is unreadable on the slice',
        );
      }
      expect(
        _contrast(theme.primaryColor, theme.primaryTextColor),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        _contrast(theme.mainBkg, theme.textColor),
        greaterThanOrEqualTo(3.0),
      );
    });
  }

  test('maps text metrics that take part in layout', () {
    final theme = MaterialMermaidTheme.fromColorScheme(
      ColorScheme.fromSeed(seedColor: const Color(0xff3457d5)),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontFamily: 'Example Sans', fontSize: 18),
      ),
    );
    expect(theme.fontFamily, 'Example Sans');
    expect(theme.fontSize, 18);

    final defaults = MaterialMermaidTheme.fromColorScheme(
      ColorScheme.fromSeed(seedColor: const Color(0xff3457d5)),
    );
    expect(defaults.fontFamily, core.MermaidTheme.defaultTheme.fontFamily);
    expect(defaults.fontSize, core.MermaidTheme.defaultTheme.fontSize);
  });

  testWidgets('ThemeData brightness switch rebuilds diagrams with new roles', (
    tester,
  ) async {
    var mode = ThemeMode.light;
    late StateSetter update;
    final renderedThemes = <core.MermaidTheme>[];
    const source = '''
sequenceDiagram
  participant A as App
  participant S as Service
  A->>S: Request
  Note right of S: Validate
  S-->>A: Response
''';

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MaterialApp(
            theme: ThemeData(
              colorSchemeSeed: const Color(0xff3457d5),
              brightness: Brightness.light,
            ),
            darkTheme: ThemeData(
              colorSchemeSeed: const Color(0xff79a7ff),
              brightness: Brightness.dark,
            ),
            themeMode: mode,
            home: Builder(
              builder: (context) => MermaidDiagram(
                source: source,
                theme: MaterialMermaidTheme.fromTheme(Theme.of(context)),
                sceneRenderer: (value, theme) {
                  renderedThemes.add(theme);
                  return core.Mermaid(
                    measurer: const FlutterTextMeasurer(),
                    theme: theme,
                  ).render(value);
                },
              ),
            ),
          );
        },
      ),
    );
    await tester.pump();
    final light = renderedThemes.single;
    expect(light.background, isNot(const core.Color(0xff000000)));

    update(() => mode = ThemeMode.dark);
    await tester.pumpAndSettle();
    final dark = renderedThemes.last;

    expect(renderedThemes.length, greaterThanOrEqualTo(2));
    expect(dark, isNot(light));
    expect(dark.background, isNot(light.background));
    expect(dark.actorBkg, isNot(light.actorBkg));
    expect(dark.actorTextColor, isNot(light.actorTextColor));
    expect(dark.noteBkgColor, isNot(light.noteBkgColor));
  });

  testWidgets('diagram-specific Material role changes rebuild the scene', (
    tester,
  ) async {
    final baseScheme = ColorScheme.fromSeed(seedColor: const Color(0xff3457d5));
    final first = MaterialMermaidTheme.fromColorScheme(baseScheme);
    final second = MaterialMermaidTheme.fromColorScheme(
      baseScheme.copyWith(
        tertiaryContainer: const Color(0xff123456),
        onTertiaryContainer: const Color(0xfffefefe),
      ),
    );
    expect(second.background, first.background);
    expect(second.noteBkgColor, isNot(first.noteBkgColor));
    expect(second, isNot(first));

    var current = first;
    late StateSetter update;
    final renderedThemes = <core.MermaidTheme>[];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MaterialApp(
            home: MermaidDiagram(
              source: 'sequenceDiagram\nA->>B: message',
              theme: current,
              sceneRenderer: (value, theme) {
                renderedThemes.add(theme);
                return core.Mermaid(
                  measurer: const FlutterTextMeasurer(),
                  theme: theme,
                ).render(value);
              },
            ),
          );
        },
      ),
    );
    await tester.pump();
    expect(renderedThemes, [first]);

    update(() => current = second);
    await tester.pump();
    expect(renderedThemes, [first, second]);
  });

  test(
    'representative flow and sequence diagrams render in light and dark',
    () async {
      final light = MaterialMermaidTheme.fromTheme(
        ThemeData(colorSchemeSeed: const Color(0xff3457d5)),
      );
      final dark = MaterialMermaidTheme.fromTheme(
        ThemeData(
          colorSchemeSeed: const Color(0xff79a7ff),
          brightness: Brightness.dark,
        ),
      );
      const sources = <String, String>{
        'flow': '''
flowchart LR
  subgraph Client
    A[Request] --> B{Valid?}
  end
  B -->|yes| C[Complete]
  B -->|no| D[Retry]
''',
        'sequence': '''
sequenceDiagram
  participant A as App
  participant S as Service
  A->>S: Request
  Note right of S: Validate
  S-->>A: Response
''',
      };
      final evidenceDir = Platform.environment['MERMAID_THEME_EVIDENCE_DIR'];

      for (final MapEntry(key: name, value: source) in sources.entries) {
        final lightPng = await renderToPng(source, theme: light);
        final darkPng = await renderToPng(source, theme: dark);
        expect(lightPng, isNot(equals(darkPng)));
        expect(lightPng.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
        expect(darkPng.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
        if (evidenceDir != null) {
          final directory = Directory(evidenceDir)..createSync(recursive: true);
          File('${directory.path}/$name-light.png').writeAsBytesSync(lightPng);
          File('${directory.path}/$name-dark.png').writeAsBytesSync(darkPng);
        }
      }
    },
  );
}

/// WCAG 2.1 contrast ratio between two opaque colors.
double _contrast(core.Color a, core.Color b) {
  final la = Color(a.value).computeLuminance();
  final lb = Color(b.value).computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
