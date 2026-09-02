import 'package:flutter/material.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

final _lightScheme =
    ColorScheme.fromSeed(
      seedColor: const Color(0xff0b57d0),
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xff0b57d0),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xffd7e3ff),
      onPrimaryContainer: const Color(0xff001b3f),
      secondary: const Color(0xff2864b7),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xffd8e6ff),
      onSecondaryContainer: const Color(0xff001b3f),
      tertiary: const Color(0xff006a78),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xffa9edff),
      onTertiaryContainer: const Color(0xff001f25),
      surface: Colors.white,
      onSurface: const Color(0xff111418),
      onSurfaceVariant: const Color(0xff3f464d),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xfff7f8fa),
      surfaceContainer: const Color(0xfff1f3f5),
      surfaceContainerHigh: const Color(0xffe9ecef),
      surfaceContainerHighest: const Color(0xffdee2e6),
      outline: const Color(0xff687078),
      outlineVariant: const Color(0xffc4c9cf),
    );

final _darkScheme =
    ColorScheme.fromSeed(
      seedColor: const Color(0xff8ab4f8),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xff8ab4f8),
      onPrimary: const Color(0xff002f65),
      primaryContainer: const Color(0xff174a7e),
      onPrimaryContainer: const Color(0xffd7e3ff),
      secondary: const Color(0xff7fb3ff),
      onSecondary: const Color(0xff00315f),
      secondaryContainer: const Color(0xff164976),
      onSecondaryContainer: const Color(0xffd8e6ff),
      tertiary: const Color(0xff65d6e8),
      onTertiary: const Color(0xff00363e),
      tertiaryContainer: const Color(0xff004f5a),
      onTertiaryContainer: const Color(0xffa9edff),
      surface: const Color(0xff101214),
      onSurface: const Color(0xffedf0f2),
      onSurfaceVariant: const Color(0xffc4c9cf),
      surfaceContainerLowest: const Color(0xff0b0d0f),
      surfaceContainerLow: const Color(0xff17191c),
      surfaceContainer: const Color(0xff1d2023),
      surfaceContainerHigh: const Color(0xff25282c),
      surfaceContainerHighest: const Color(0xff303438),
      outline: const Color(0xff9299a1),
      outlineVariant: const Color(0xff444b52),
    );

/// The website's live demonstration of the one-call Material theme bridge.
class MaterialThemeDemo extends StatefulWidget {
  const MaterialThemeDemo({
    super.key,
    required this.source,
    this.onRequestFullscreen,
  });

  final String source;
  final VoidCallback? onRequestFullscreen;

  @override
  State<MaterialThemeDemo> createState() => _MaterialThemeDemoState();
}

class _MaterialThemeDemoState extends State<MaterialThemeDemo> {
  ThemeMode _themeMode = ThemeMode.light;
  bool _useMaterialTheme = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: _lightScheme),
      darkTheme: ThemeData(colorScheme: _darkScheme),
      themeMode: _themeMode,
      home: Builder(
        builder: (context) {
          final materialTheme = Theme.of(context);
          final colors = materialTheme.colorScheme;
          final dark = materialTheme.brightness == Brightness.dark;
          final mermaidTheme = _useMaterialTheme
              ? MaterialMermaidTheme.fromTheme(materialTheme)
              : dark
              ? core.MermaidTheme.darkTheme
              : core.MermaidTheme.defaultTheme;
          final diagramBackground = Color(mermaidTheme.background.value);
          return Material(
            color: colors.surface,
            child: Stack(
              children: [
                Positioned.fill(
                  child: MermaidView(
                    source: widget.source,
                    theme: mermaidTheme,
                    backgroundColor: diagramBackground,
                    keepLastGoodSceneOnError: false,
                    onRequestFullscreen: widget.onRequestFullscreen,
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: dark ? 'Use light theme' : 'Use dark theme',
                        child: IconButton.filledTonal(
                          key: const ValueKey('brightness-theme-toggle'),
                          onPressed: () => setState(() {
                            _themeMode = dark
                                ? ThemeMode.light
                                : ThemeMode.dark;
                          }),
                          icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        key: const ValueKey('material-theme-toggle'),
                        selected: _useMaterialTheme,
                        onSelected: (selected) =>
                            setState(() => _useMaterialTheme = selected),
                        avatar: const Icon(Icons.palette_outlined, size: 18),
                        label: const Text('Material theme'),
                        tooltip: _useMaterialTheme
                            ? 'Use native Mermaid theme'
                            : 'Use Material theme bridge',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
