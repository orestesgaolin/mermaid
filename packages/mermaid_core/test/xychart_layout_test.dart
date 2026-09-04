/// xychart config validation and d3 scale parity.
library;

import 'package:mermaid_core/src/diagrams/xychart/xychart.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:test/test.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());

List<SceneNode> _flatten(List<SceneNode> nodes) => [
  for (final node in nodes) ...[
    node,
    if (node is SceneGroup) ..._flatten(node.children),
  ],
];

/// The two straight axis lines a chart draws: a vertical one for the value
/// axis and a horizontal one for the category axis. Both span their axis'
/// scale range, so their endpoints are the range the scales map into.
({Point a, Point b}) _axisLine(RenderScene scene, {required bool vertical}) {
  final lines = _flatten(scene.nodes)
      .whereType<SceneShape>()
      .map((shape) => shape.geometry)
      .whereType<PathGeometry>()
      .where((path) => path.commands.length == 2)
      .map(
        (path) => (
          a: (path.commands[0] as MoveTo).p,
          b: (path.commands[1] as LineTo).p,
        ),
      )
      .where(
        (segment) => vertical
            ? (segment.a.x - segment.b.x).abs() < 1e-9 &&
                  (segment.a.y - segment.b.y).abs() > 1
            : (segment.a.y - segment.b.y).abs() < 1e-9 &&
                  (segment.a.x - segment.b.x).abs() > 1,
      )
      .toList();
  // Ticks are short marks perpendicular to their axis; the axis line itself is
  // the longest segment in its direction.
  lines.sort((x, y) {
    final lx = vertical ? (x.a.y - x.b.y).abs() : (x.a.x - x.b.x).abs();
    final ly = vertical ? (y.a.y - y.b.y).abs() : (y.a.x - y.b.x).abs();
    return ly.compareTo(lx);
  });
  return lines.first;
}

List<Rect> _bars(RenderScene scene) => _flatten(scene.nodes)
    .whereType<SceneShape>()
    .where((shape) => shape.fill != null && shape.stroke == null)
    .map((shape) => shape.geometry)
    .whereType<RectGeometry>()
    .map((geometry) => geometry.rect)
    .toList();

void main() {
  group('config validation', () {
    // The parser must never let a config value drive the scene to a negative
    // or non-finite size; every out-of-range value falls back to the upstream
    // default (700 x 500, plotReservedSpacePercent 50).
    const body = '''
xychart-beta
    x-axis [a, b, c]
    bar [10, 20, 30]
''';

    String withConfig(String yaml) =>
        '---\nconfig:\n  xyChart:\n$yaml---\n$body';

    const bad = {
      'negative': '    width: -700\n    height: -500\n',
      'zero': '    width: 0\n    height: 0\n',
      'non-finite': '    width: Infinity\n    height: NaN\n',
      'non-numeric': '    width: wide\n    height: tall\n',
    };
    bad.forEach((label, yaml) {
      test('$label width/height falls back to the default canvas', () {
        final scene = _renderer.render(withConfig(yaml));
        expect(scene.size, const Size(700, 500), reason: label);
        expect(_bars(scene), hasLength(3), reason: label);
      });
    });

    test('a valid width/height is still honoured', () {
      final scene = _renderer.render(
        withConfig('    width: 900\n    height: 400\n'),
      );
      expect(scene.size, const Size(900, 400));
    });

    const badPercent = {
      'negative': '-40',
      'zero': '0',
      'below the schema minimum of 30': '10',
      'non-finite': 'Infinity',
    };
    badPercent.forEach((label, value) {
      test('plotReservedSpacePercent $label falls back to 50', () {
        final fallback = _renderer.render(
          withConfig('    plotReservedSpacePercent: $value\n'),
        );
        final reference = _renderer.render(
          withConfig('    plotReservedSpacePercent: 50\n'),
        );
        final axis = _axisLine(fallback, vertical: true);
        final expected = _axisLine(reference, vertical: true);
        expect(
          (axis.a.y - axis.b.y).abs(),
          closeTo((expected.a.y - expected.b.y).abs(), 1e-9),
          reason: label,
        );
      });
    });

    test('an out-of-range axis metric falls back to its default', () {
      // `tickWidth` has a schema minimum of 1; -3 would paint an invisible
      // (or, in a backend that clamps, an arbitrary) stroke.
      final scene = _renderer.render(
        withConfig('    xAxis:\n      tickWidth: -3\n'),
      );
      final strokes = _flatten(scene.nodes)
          .whereType<SceneShape>()
          .map((shape) => shape.stroke?.width)
          .whereType<double>();
      expect(strokes, isNotEmpty);
      expect(strokes.every((width) => width > 0), isTrue);
    });
  });

  group('orientation has a single source of truth', () {
    test('the `horizontal` header is folded into the resolved config', () {
      final chart = parseXyChart(
        'xychart-beta horizontal\n  x-axis [a, b]\n  bar [1, 2]\n',
      );
      expect(chart.horizontal, isTrue);
      expect(chart.config.horizontal, isTrue, reason: 'config is the source');
    });

    test('chartOrientation reaches the chart through the config', () {
      final chart = parseXyChart(
        '---\nconfig:\n  xyChart:\n    chartOrientation: horizontal\n'
        '---\nxychart-beta\n  x-axis [a, b]\n  bar [1, 2]\n',
      );
      expect(chart.horizontal, isTrue);
      expect(chart.config.horizontal, isTrue);
    });
  });

  test('an all-equal value domain maps to the middle of the range', () {
    // d3's `scaleLinear` normalizes a zero-extent domain to a constant 0.5,
    // so every bar reaches the vertical midpoint of the value axis instead of
    // filling the plot from top to bottom.
    final scene = _renderer.render(
      'xychart-beta\n  x-axis [a, b, c]\n  bar [5, 5, 5]\n',
    );
    final axis = _axisLine(scene, vertical: true);
    final top = axis.a.y < axis.b.y ? axis.a.y : axis.b.y;
    final bottom = axis.a.y < axis.b.y ? axis.b.y : axis.a.y;

    final bars = _bars(scene);
    expect(bars, hasLength(3));
    for (final bar in bars) {
      expect(bar.top, closeTo((top + bottom) / 2, 1e-9));
      expect(bar.height, closeTo((bottom - top) / 2, 1e-9));
    }
  });

  test('a single category is centered in the plot, not pinned left', () {
    // d3 `scaleBand` shifts the origin by `(span - step * (n - 1)) * align`;
    // that shift is zero from two categories up but half the span for one.
    final one = _renderer.render(
      'xychart-beta\n  x-axis [only]\n  y-axis 0 --> 10\n  bar [5]\n',
    );
    final axis = _axisLine(one, vertical: false);
    final left = axis.a.x < axis.b.x ? axis.a.x : axis.b.x;
    final right = axis.a.x < axis.b.x ? axis.b.x : axis.a.x;

    final bars = _bars(one);
    expect(bars, hasLength(1));
    expect(bars.single.center.x, closeTo((left + right) / 2, 1e-9));

    // Two categories still sit on the ends of the inner range.
    final two = _renderer.render(
      'xychart-beta\n  x-axis [a, b]\n  y-axis 0 --> 10\n  bar [5, 5]\n',
    );
    final pair = _bars(two)..sort((a, b) => a.center.x.compareTo(b.center.x));
    expect(pair, hasLength(2));
    final twoAxis = _axisLine(two, vertical: false);
    final twoMid = (twoAxis.a.x + twoAxis.b.x) / 2;
    expect(pair.first.center.x, lessThan(twoMid));
    expect(pair.last.center.x, greaterThan(twoMid));
    expect(
      (pair.first.center.x + pair.last.center.x) / 2,
      closeTo(twoMid, 1e-9),
    );
  });
}
