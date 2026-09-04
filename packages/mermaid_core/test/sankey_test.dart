/// Tests for the sankey diagram.
library;

import 'support/fixtures.dart';
import 'dart:math' as math;

import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/detect.dart';
import 'package:mermaid_core/src/diagrams/sankey/sankey.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/ir/scene_utils.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

List<SceneNode> flatten(List<SceneNode> nodes) => [
  for (final n in nodes) ...[n, if (n is SceneGroup) ...flatten(n.children)],
];

bool pathsCross(PathGeometry a, PathGeometry b) {
  final aStart = (a.commands.first as MoveTo).p;
  final aCurve = a.commands.last as CubicTo;
  final bStart = (b.commands.first as MoveTo).p;
  final bCurve = b.commands.last as CubicTo;
  final left = math.max(aStart.x, bStart.x);
  final right = math.min(aCurve.p.x, bCurve.p.x);
  double? previous;
  for (var i = 0; i <= 24; i++) {
    final x = left + (right - left) * (i + 0.25) / 24.5;
    final difference = pathYAt(a, x) - pathYAt(b, x);
    if (difference.abs() <= 1e-6) continue;
    if (previous != null && difference.sign != previous.sign) return true;
    previous = difference;
  }
  return false;
}

double pathYAt(PathGeometry path, double x) {
  final start = (path.commands.first as MoveTo).p;
  final curve = path.commands.last as CubicTo;
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 20; i++) {
    final t = (low + high) / 2;
    final mt = 1 - t;
    final curveX =
        mt * mt * mt * start.x +
        3 * mt * mt * t * curve.c1.x +
        3 * mt * t * t * curve.c2.x +
        t * t * t * curve.p.x;
    if (curveX < x) {
      low = t;
    } else {
      high = t;
    }
  }
  final t = (low + high) / 2;
  final mt = 1 - t;
  return mt * mt * mt * start.y +
      3 * mt * mt * t * curve.c1.y +
      3 * mt * t * t * curve.c2.y +
      t * t * t * curve.p.y;
}

String pathSignature(RenderScene scene) => flatten(scene.nodes)
    .whereType<SceneShape>()
    .where((shape) => shape.geometry is PathGeometry)
    .map((shape) {
      final path = shape.geometry as PathGeometry;
      return path.commands.map((command) {
        return switch (command) {
          MoveTo(:final p) => 'M${p.x},${p.y}',
          CubicTo(:final c1, :final c2, :final p) =>
            'C${c1.x},${c1.y},${c2.x},${c2.y},${p.x},${p.y}',
          _ => command.runtimeType.toString(),
        };
      }).join();
    })
    .join('|');

void main() {
  test('detects sankey / sankey-beta', () {
    expect(detectDiagramType('sankey-beta\na,b,1'), DiagramType.sankey);
    expect(detectDiagramType('sankey\na,b,1'), DiagramType.sankey);
  });

  group('parse', () {
    test('collects links and unique nodes in order', () {
      final s = parseSankey('''
sankey-beta
A,B,5
B,C,3
A,C,2
''');
      expect(s.nodes, ['A', 'B', 'C']);
      expect(s.links.length, 3);
      expect(s.links.first.value, 5);
    });

    test('honors quoted fields with commas', () {
      final s = parseSankey('sankey-beta\n"a, b",C,1');
      expect(s.nodes.first, 'a, b');
    });

    test('rejects a non-numeric value', () {
      expect(
        () => parseSankey('sankey-beta\nA,B,x'),
        throwsA(isA<MermaidParseException>()),
      );
    });

    test('rejects values that parse but cannot be laid out', () {
      for (final literal in ['NaN', 'Infinity', '-Infinity']) {
        expect(
          () => parseSankey('sankey-beta\nA,B,$literal'),
          throwsA(
            isA<MermaidParseException>().having(
              (error) => error.message,
              'message',
              contains('finite'),
            ),
          ),
          reason: literal,
        );
      }
    });
  });

  group('layout', () {
    test('places nodes in columns by longest path; widths track flow', () {
      final scene = layoutSankey(
        parseSankey('sankey-beta\nA,B,10\nB,C,10'),
        measurer: measurer,
        theme: theme,
      );
      final rects = flatten(scene.nodes)
          .whereType<SceneShape>()
          .where((s) => s.geometry is RectGeometry)
          .toList();
      // Three node bars at three distinct x columns.
      final xs = rects
          .map((s) => (s.geometry as RectGeometry).rect.left)
          .toSet();
      expect(xs.length, 3);
      // Ribbons are filled bezier paths.
      final ribbons = flatten(scene.nodes).whereType<SceneShape>().where(
        (s) => s.geometry is PathGeometry && s.stroke != null,
      );
      expect(ribbons.length, 2);
      // Labels present. showValues defaults true upstream, so each node label
      // is "<name>\n<value>"; check the name on the first line.
      final names = flatten(
        scene.nodes,
      ).whereType<SceneText>().map((t) => t.text.split('\n').first);
      expect(names, containsAll(['A', 'B', 'C']));
    });

    test('layoutSankey takes its options as a SankeyConfig', () {
      final scene = layoutSankey(
        parseSankey('sankey-beta\nA,B,10'),
        measurer: measurer,
        theme: theme,
        config: const SankeyConfig(width: 300, height: 200, showValues: false),
      );
      final rects = flatten(scene.nodes)
          .whereType<SceneShape>()
          .map((shape) => shape.geometry)
          .whereType<RectGeometry>()
          .map((geometry) => geometry.rect)
          .toList();
      final bounds = rects.reduce((a, b) => a.union(b));
      expect(bounds.width, closeTo(300, 1e-6));
      expect(bounds.height, lessThanOrEqualTo(200 + 1e-6));
      expect(
        flatten(scene.nodes).whereType<SceneText>().map((t) => t.text),
        ['A', 'B'],
      );
    });

    test('a custom node color does not consume a palette slot', () {
      // d3 keys its ordinal scale by node id and only pulls the next palette
      // entry for a node it has to color itself, so B — the first node without
      // an explicit color — must still get the first palette entry.
      Color fillOf(RenderScene scene, int index) => flatten(scene.nodes)
          .whereType<SceneShape>()
          .where((shape) => shape.geometry is RectGeometry)
          .elementAt(index)
          .fill!
          .color;

      final plain = layoutSankey(
        parseSankey('sankey-beta\nA,B,10'),
        measurer: measurer,
        theme: theme,
      );
      final firstPaletteColor = fillOf(plain, 0);
      final secondPaletteColor = fillOf(plain, 1);
      expect(firstPaletteColor, isNot(secondPaletteColor));

      const custom = Color(0xff123456);
      final tinted = layoutSankey(
        parseSankey('sankey-beta\nA,B,10'),
        measurer: measurer,
        theme: theme,
        config: const SankeyConfig(nodeColors: {'A': custom}),
      );
      expect(fillOf(tinted, 0), custom);
      expect(fillOf(tinted, 1), firstPaletteColor);
    });

    test('a value-less label is vertically centered on its node', () {
      final scene = layoutSankey(
        parseSankey('sankey-beta\nA,B,10\nA,C,10'),
        measurer: measurer,
        theme: theme,
        config: const SankeyConfig(showValues: false),
      );
      final rects = flatten(scene.nodes)
          .whereType<SceneShape>()
          .where((shape) => shape.geometry is RectGeometry)
          .map((shape) => (shape.geometry as RectGeometry).rect)
          .toList();
      final labels = flatten(scene.nodes).whereType<SceneText>().toList();
      expect(labels, hasLength(rects.length));
      for (var i = 0; i < rects.length; i++) {
        expect(
          labels[i].bounds.center.y,
          closeTo(rects[i].center.y, 1e-9),
          reason: 'label ${labels[i].text} must sit on its node centre',
        );
      }
    });
  });

  group('Mermaid.render configuration', () {
    const renderer = Mermaid(measurer: measurer, theme: theme);

    test('fixture frontmatter controls extent, values, and gradient links', () {
      final source = readFixture('upstream_sankey/03.mmd');
      final sankey = parseSankey(source);
      final scene = renderer.render(source);
      final nodes = flatten(scene.nodes);
      final shapes = nodes
          .whereType<SceneShape>()
          .where(
            (s) => s.geometry is RectGeometry || s.geometry is PathGeometry,
          )
          .toList();
      final diagramBounds = sceneBounds(shapes)!;
      final texts = nodes.whereType<SceneText>().toList();
      final ribbons = shapes.where((s) => s.geometry is PathGeometry).toList();

      // The configured d3-sankey extent is preserved before labels and the
      // outer 12 px scene padding expand the public scene bounds.
      expect(diagramBounds.width, closeTo(1200, 1e-6));
      expect(diagramBounds.height, closeTo(600, 1e-6));
      expect(scene.size.width, greaterThan(1200));
      // `showValues: false` in the fixture frontmatter, so every node gets
      // exactly one single-line label and nothing else is written.
      expect(texts, hasLength(sankey.nodes.length));
      expect(
        texts.map((text) => text.text).toSet(),
        equals(sankey.nodes.toSet()),
      );
      expect(texts.every((text) => !text.text.contains('\n')), isTrue);
      expect(ribbons.every((shape) => shape.stroke?.gradient != null), isTrue);
      expect(
        ribbons.every((shape) => shape.blendMode == SceneBlendMode.multiply),
        isTrue,
      );

      final rects = nodes
          .whereType<SceneShape>()
          .where((shape) => shape.geometry is RectGeometry)
          .toList();
      expect(
        rects.every(
          (shape) => (shape.geometry as RectGeometry).rect.height >= 2.0 - 1e-6,
        ),
        isTrue,
      );
      double topOf(String name) {
        final index = sankey.nodes.indexOf(name);
        return (rects[index].geometry as RectGeometry).rect.top;
      }

      PathGeometry ribbon(String source, String target) {
        final index = sankey.links.indexWhere(
          (link) => link.source == source && link.target == target,
        );
        return ribbons[index].geometry as PathGeometry;
      }

      // d3-sankey reorders each column by the connected nodes' breadth during
      // relaxation. First-seen stacking puts both pairs in the reverse order.
      expect(
        topOf("Agricultural 'waste'"),
        lessThan(topOf('UK land based bioenergy')),
      );
      expect(topOf('Wind'), lessThan(topOf('Pumped heat')));
      expect(topOf('Marine algae'), lessThan(topOf('Other waste')));
      expect(topOf('Gas imports'), lessThan(topOf('Tidal')));
      expect(
        pathsCross(
          ribbon('Marine algae', 'Bio-conversion'),
          ribbon('Other waste', 'Solid'),
        ),
        isFalse,
      );
      expect(
        pathsCross(
          ribbon('Gas imports', 'Ngas'),
          ribbon('Tidal', 'Electricity grid'),
        ),
        isFalse,
      );

      final repeated = renderer.render(source);
      expect(pathSignature(repeated), pathSignature(scene));

      // Compression can reduce computed lane widths below one pixel. The
      // crossing refinement must use the effective painted width and keep the
      // visible hairlines ordered.
      final compressed = renderer.render(
        source.replaceFirst('height: 600', 'height: 30\n    nodePadding: 100'),
      );
      final compressedRibbons = flatten(compressed.nodes)
          .whereType<SceneShape>()
          .where((shape) => shape.geometry is PathGeometry)
          .toList();
      expect(
        compressedRibbons.every((shape) => (shape.stroke?.width ?? 0) >= 2),
        isTrue,
      );
      PathGeometry compressedRibbon(String source, String target) {
        final index = sankey.links.indexWhere(
          (link) => link.source == source && link.target == target,
        );
        return compressedRibbons[index].geometry as PathGeometry;
      }

      expect(
        pathsCross(
          compressedRibbon('Marine algae', 'Bio-conversion'),
          compressedRibbon('Other waste', 'Solid'),
        ),
        isFalse,
      );
      expect(
        pathsCross(
          compressedRibbon('Gas imports', 'Ngas'),
          compressedRibbon('Tidal', 'Electricity grid'),
        ),
        isFalse,
      );
    });

    test('two configs change size, alignment, values, and link color', () {
      const data = '''
sankey
A,B,10
A,C,5
B,D,10
''';
      const leftSource = '''
---
config:
  sankey:
    width: 300
    height: 200
    showValues: false
    nodeAlignment: left
    linkColor: source
---
$data''';
      const justifyTarget = '''
---
config:
  sankey:
    width: 900
    height: 400
    showValues: true
    nodeAlignment: justify
    linkColor: target
---
$data''';

      final left = flatten(renderer.render(leftSource).nodes);
      final justify = flatten(renderer.render(justifyTarget).nodes);
      final leftRects = left
          .whereType<SceneShape>()
          .where((s) => s.geometry is RectGeometry)
          .toList();
      final justifyRects = justify
          .whereType<SceneShape>()
          .where((s) => s.geometry is RectGeometry)
          .toList();
      final leftRibbons = left
          .whereType<SceneShape>()
          .where((s) => s.geometry is PathGeometry)
          .toList();
      final targetRibbons = justify
          .whereType<SceneShape>()
          .where((s) => s.geometry is PathGeometry)
          .toList();

      expect(sceneBounds(leftRects)!.width, closeTo(300, 1e-6));
      expect(sceneBounds(justifyRects)!.width, closeTo(900, 1e-6));
      expect(sceneBounds(leftRects)!.height, closeTo(200, 1e-6));
      expect(sceneBounds(justifyRects)!.height, closeTo(400, 1e-6));
      expect(
        left.whereType<SceneText>().every((text) => !text.text.contains('\n')),
        isTrue,
      );
      expect(
        justify.whereType<SceneText>().every(
          (text) => text.text.contains('\n'),
        ),
        isTrue,
      );

      // C is the third first-seen node. Left alignment leaves this early sink
      // in the middle column; justify alignment moves it to the final column.
      final leftCX = (leftRects[2].geometry as RectGeometry).rect.left;
      final justifyCX = (justifyRects[2].geometry as RectGeometry).rect.left;
      final justifyDX = (justifyRects[3].geometry as RectGeometry).rect.left;
      expect(
        leftCX,
        lessThan((leftRects[3].geometry as RectGeometry).rect.left),
      );
      expect(justifyCX, closeTo(justifyDX, 1e-6));

      expect(leftRibbons.first.stroke?.gradient, isNull);
      expect(leftRibbons.first.stroke?.color, const Color(0x804e79a7));
      expect(targetRibbons.first.stroke?.gradient, isNull);
      expect(targetRibbons.first.stroke?.color, const Color(0x80f28e2c));
    });

    test('link opacity multiplies configured alpha', () {
      const semiTransparent = '''
---
config:
  sankey:
    linkColor: '#ff000080'
---
sankey
A,B,1
''';
      const transparent = '''
---
config:
  sankey:
    linkColor: transparent
---
sankey
A,B,1
''';
      const gradient = '''
---
config:
  sankey:
    linkColor: gradient
    nodeColors:
      A: '#ff000080'
      B: transparent
---
sankey
A,B,1
''';

      SceneShape ribbon(String source) => flatten(renderer.render(source).nodes)
          .whereType<SceneShape>()
          .firstWhere((shape) => shape.geometry is PathGeometry);

      expect(ribbon(semiTransparent).stroke?.color, const Color(0x40ff0000));
      expect(ribbon(transparent).stroke?.color, const Color(0x00000000));
      expect(ribbon(gradient).stroke?.gradient?.colors, [
        const Color(0x40ff0000),
        const Color(0x00000000),
      ]);
    });

    test('large node padding stays within a small configured height', () {
      const source = '''
---
config:
  sankey:
    height: 30
    nodePadding: 100
    showValues: false
---
sankey
A,X,1
B,Y,1
C,Z,1
''';

      final scene = renderer.render(source);
      final rects = flatten(scene.nodes)
          .whereType<SceneShape>()
          .where((shape) => shape.geometry is RectGeometry)
          .toList();

      expect(rects, hasLength(6));
      // Labels can translate the complete scene, so compare the node span,
      // not its absolute post-normalization coordinates.
      expect(sceneBounds(rects)!.height, lessThanOrEqualTo(30 + 1e-6));
    });

    test('thin single-link nodes match the painted lane width', () {
      const source = '''
---
config:
  sankey:
    height: 100
    nodePadding: 12
    showValues: false
---
sankey
A,X,100
B,Y,10
C,Z,0.1
''';

      final nodes = flatten(renderer.render(source).nodes);
      final rects = nodes
          .whereType<SceneShape>()
          .where((shape) => shape.geometry is RectGeometry)
          .map((shape) => (shape.geometry as RectGeometry).rect)
          .toList();
      final ribbons = nodes
          .whereType<SceneShape>()
          .where((shape) => shape.geometry is PathGeometry)
          .toList();

      final rectBounds = rects.reduce((a, b) => a.union(b));
      expect(rectBounds.height, lessThanOrEqualTo(100 + 1e-6));
      // `_kMinVisualFlowWidth` (2 px) is the floor the layout keeps for a node
      // bar and its lane so a near-zero flow stays visible; C,Z,0.1 against a
      // 100 px height scales below it, so it must land exactly on the floor.
      const minVisualFlowWidth = 2.0;
      expect(rects[4].height, closeTo(minVisualFlowWidth, 1e-6));
      final largeWidth = ribbons[0].stroke!.width;
      final mediumWidth = ribbons[1].stroke!.width;
      final smallWidth = ribbons[2].stroke!.width;
      expect(largeWidth / mediumWidth, closeTo(10, 1e-6));
      expect(smallWidth, closeTo(minVisualFlowWidth, 1e-6));
      expect(rects[0].height, closeTo(largeWidth, 1e-6));
      expect(rects[2].height, closeTo(mediumWidth, 1e-6));
      expect(rects[4].height, closeTo(smallWidth, 1e-6));
      final smallPath = ribbons[2].geometry as PathGeometry;
      final start = (smallPath.commands.first as MoveTo).p;
      final end = (smallPath.commands.last as CubicTo).p;
      expect(start.y, closeTo(rects[4].center.y, 1e-6));
      expect(end.y, closeTo(rects[5].center.y, 1e-6));

      final tiny = renderer.render(
        source.replaceFirst('height: 100', 'height: 6'),
      );
      final tinyRects = flatten(tiny.nodes)
          .whereType<SceneShape>()
          .where((shape) => shape.geometry is RectGeometry)
          .toList();
      expect(sceneBounds(tinyRects)!.height, lessThanOrEqualTo(6 + 1e-6));
    });

    test('invalid values use renderer defaults', () {
      const source = '''
---
config:
  sankey:
    width: -2
    height: no
    nodePadding: -1
    nodeAlignment: diagonal
    linkColor: not-a-color
    showValues: sometimes
---
sankey
A,B,1
B,C,1
''';

      final nodes = flatten(renderer.render(source).nodes);
      final rects = nodes
          .whereType<SceneShape>()
          .where((s) => s.geometry is RectGeometry)
          .toList();
      final ribbon = nodes.whereType<SceneShape>().firstWhere(
        (s) => s.geometry is PathGeometry,
      );

      expect(sceneBounds(rects)!.width, closeTo(600, 1e-6));
      expect(sceneBounds(rects)!.height, closeTo(600, 1e-6));
      expect(
        nodes.whereType<SceneText>().every((text) => text.text.contains('\n')),
        isTrue,
      );
      expect(ribbon.stroke?.gradient, isNotNull);
    });
  });
}
