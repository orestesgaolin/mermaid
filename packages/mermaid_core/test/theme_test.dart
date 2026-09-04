/// Value semantics of [MermaidTheme]: equality, hashing, and what `copyWith`
/// carries over.
library;

import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

void main() {
  group('MermaidTheme value semantics', () {
    test('separately built equal themes agree on == and hashCode', () {
      final a = MermaidTheme.named('forest').copyWith(fontSize: 18);
      final b = MermaidTheme.named('forest').copyWith(fontSize: 18);

      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      // The hash is cached per instance; reading it twice must not change it.
      expect(a.hashCode, a.hashCode);
      expect({a, b}, hasLength(1));
    });

    test('the identity shortcut does not hide a real difference', () {
      expect(MermaidTheme.defaultTheme, MermaidTheme.defaultTheme);
      expect(MermaidTheme.defaultTheme, isNot(MermaidTheme.darkTheme));
      expect(
        MermaidTheme.defaultTheme.hashCode,
        isNot(MermaidTheme.darkTheme.hashCode),
      );
    });

    test('copyWith replaces base fields and keeps every other palette', () {
      final dark = MermaidTheme.darkTheme;
      final tuned = dark.copyWith(fontSize: 19, lineColor: dark.textColor);

      expect(tuned.fontSize, 19);
      expect(tuned.lineColor, dark.textColor);
      // Palettes have no copyWith parameter, so they come across untouched —
      // a dark theme must not silently fall back to the default plot colors.
      expect(tuned.xyChartPlotColorPalette, dark.xyChartPlotColorPalette);
      expect(
        tuned.xyChartPlotColorPalette,
        isNot(MermaidTheme.defaultTheme.xyChartPlotColorPalette),
      );
      expect(tuned.cScale, dark.cScale);
      expect(tuned.pie, dark.pie);
      expect(tuned.git, dark.git);
    });
  });
}
