/// Parse + render smoke tests for cynefin, venn, ishikawa, wardley,
/// eventmodeling and railroad.
library;

import 'package:mermaid_core/src/detect.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/mermaid.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/text/text_measurer.dart';
import 'package:mermaid_core/src/text/text_style.dart';
import 'package:test/test.dart';

const _m = Mermaid(measurer: ApproximateTextMeasurer());

/// A measurer whose line box is taller than [ApproximateTextMeasurer]'s, as a
/// real text painter's is. A layout that reserves space from a hard-coded font
/// size instead of from the measured text collides under it.
class _TallLineMeasurer implements TextMeasurer {
  const _TallLineMeasurer();

  @override
  Size measure(String text, TextStyleSpec style, {double? maxWidth}) {
    final s =
        const ApproximateTextMeasurer().measure(text, style, maxWidth: maxWidth);
    return Size(s.width, s.height * 1.35);
  }
}

const _tall = Mermaid(measurer: _TallLineMeasurer());

List<SceneNode> _flat(List<SceneNode> n) => [
      for (final x in n) ...[
        x,
        if (x is SceneGroup) ..._flat(x.children),
      ],
    ];

Iterable<String> _texts(RenderScene s) =>
    _flat(s.nodes).whereType<SceneText>().map((t) => t.text);

void main() {
  test('detect recognizes all six headers', () {
    expect(detectDiagramType('cynefin-beta\n clear'), DiagramType.cynefin);
    expect(detectDiagramType('venn-beta\n set A'), DiagramType.venn);
    expect(detectDiagramType('ishikawa-beta\n P'), DiagramType.ishikawa);
    expect(detectDiagramType('wardley-beta\n title X'), DiagramType.wardley);
    expect(detectDiagramType('eventmodeling\n tf 01 ui A'),
        DiagramType.eventModeling);
    expect(detectDiagramType('railroad-diagram\n a = "x" ;'),
        DiagramType.railroad);
  });

  test('cynefin renders domains and items', () {
    final s = _m.render('''
cynefin-beta
  title Test
  clear
    "Restart"
  complex
    "Investigate"
''');
    expect(_texts(s), containsAll(['Clear', 'Restart', 'Investigate']));
  });

  test('venn renders sets and union label', () {
    final s = _m.render('''
venn-beta
  set Frontend
  set Backend
  union Frontend,Backend["APIs"]
''');
    expect(_texts(s), containsAll(['Frontend', 'Backend', 'APIs']));
  });

  test('venn aligns equal-set and union labels on one baseline', () {
    final s = _m.render('''
venn-beta
  set Frontend
  set Backend
  union Frontend,Backend["Full-stack"]
''');
    final labels = {
      for (final text in _flat(s.nodes).whereType<SceneText>())
        if (const {'Frontend', 'Backend', 'Full-stack'}.contains(text.text))
          text.text: text.bounds.center.y,
    };

    expect(labels.keys, containsAll(['Frontend', 'Backend', 'Full-stack']));
    expect(labels['Frontend'], closeTo(labels['Full-stack']!, 0.001));
    expect(labels['Backend'], closeTo(labels['Full-stack']!, 0.001));
  });

  test('venn title uses the stylesheet font size', () {
    final s = _m.render('''
venn-beta
  title Skills overlap
  set Frontend
  set Backend
''');
    final texts = _flat(s.nodes).whereType<SceneText>();
    final title = texts.singleWhere((text) => text.text == 'Skills overlap');
    final setLabel = texts.singleWhere((text) => text.text == 'Frontend');

    // `.venn-title` pins 32px, unlike the `48 * scale` = 24px set labels.
    expect(title.style.fontSize, 32);
    expect(title.style.fontSize, greaterThan(setLabel.style.fontSize));
    // Upstream anchors the title at x="50%" of the viewBox.
    expect(title.bounds.center.x, closeTo(s.size.width / 2, 0.001));
  });

  test('venn title band keeps the title clear of the circles', () {
    // The upstream `demos/venn.html` three-set sample.
    const source = '''
venn-beta
  title Three overlapping sets
  set A
  set B
  set C
  union A,B["AB"]
  union B,C["BC"]
  union A,C["AC"]
  union A,B,C["ABC"]
''';

    // The band is sized from the measured title, so a taller line box must not
    // push the title into the circles either.
    for (final entry in {'approximate': _m, 'tall lines': _tall}.entries) {
      final s = entry.value.render(source);

      // Upstream viewBox: nothing may push the scene past 800x450.
      expect(s.size.width, 800, reason: entry.key);
      expect(s.size.height, 450, reason: entry.key);

      final nodes = _flat(s.nodes);
      final title = nodes
          .whereType<SceneText>()
          .singleWhere((text) => text.text == 'Three overlapping sets');
      final circles = nodes
          .whereType<SceneShape>()
          .map((shape) => shape.geometry)
          .whereType<CircleGeometry>()
          .toList();
      expect(circles, hasLength(3));

      expect(title.bounds.top, greaterThanOrEqualTo(0), reason: entry.key);
      for (final c in circles) {
        final box = Rect.fromCenter(c.center, c.radius * 2, c.radius * 2);
        final overlaps = title.bounds.left < box.right &&
            box.left < title.bounds.right &&
            title.bounds.top < box.bottom &&
            box.top < title.bounds.bottom;
        expect(overlaps, isFalse,
            reason: '${entry.key}: title ${title.bounds} overlaps circle $box');
      }
    }
  });

  test('ishikawa renders problem head and categories', () {
    final s = _m.render('''
ishikawa-beta
    Blurry Photo
    Process
        Out of focus
    Equipment
        Dirty lens
''');
    expect(_texts(s), containsAll(['Blurry Photo', 'Process', 'Out of focus']));
  });

  test('ishikawa sub-labels sit at the free end of their bone', () {
    final s = _m.render('''
ishikawa-beta
  Slow website
    Technology
      Old servers
''');
    final nodes = _flat(s.nodes);
    final label = nodes.whereType<SceneText>()
        .singleWhere((text) => text.text == 'Old servers');
    // The only thin horizontal segment is the sub-bone: the spine is 2px wide
    // and the cause branch is diagonal.
    final bone = nodes.whereType<SceneShape>()
        .where((shape) => shape.stroke?.width == 1)
        .map((shape) => shape.geometry).whereType<PathGeometry>()
        .where((path) => path.commands.length == 2)
        .singleWhere((path) =>
            (path.commands.first as MoveTo).p.y ==
            (path.commands.last as LineTo).p.y);
    final boneEnd = (bone.commands.last as LineTo).p;
    // End-anchored with a middle dominant baseline: the label hangs to the left
    // of the bone tip and is vertically centred on it.
    expect(label.bounds.right, closeTo(boneEnd.x, 0.001));
    expect(label.bounds.center.y, closeTo(boneEnd.y, 0.001));
    expect(label.bounds.left, lessThan(boneEnd.x));
  });

  test('ishikawa cause labels are centred in their boxes', () {
    final s = _m.render('''
ishikawa-beta
  Blurry Photo
    Process
      Camera was not focused correctly
      Subject moved during exposure
    Equipment
      Dirty lens
''');
    final nodes = _flat(s.nodes);
    for (final name in ['Process', 'Equipment']) {
      final label =
          nodes.whereType<SceneText>().singleWhere((text) => text.text == name);
      final box = nodes.whereType<SceneShape>()
          .map((shape) => shape.geometry).whereType<RectGeometry>()
          .map((geometry) => geometry.rect)
          .singleWhere((rect) =>
              rect.top < label.bounds.center.y &&
              rect.bottom > label.bounds.center.y);
      expect(label.bounds.center.x, closeTo(box.center.x, 0.001),
          reason: '$name label is off-centre horizontally');
      expect(label.bounds.center.y, closeTo(box.center.y, 0.001),
          reason: '$name label is off-centre vertically');
    }
  });

  test('ishikawa stacks a wrapped sub-label without overlapping lines', () {
    final s = _m.render('''
ishikawa-beta
  Blurry Photo
    Process
      Camera was not focused correctly
      Subject moved during exposure
''');
    final texts = _flat(s.nodes).whereType<SceneText>();
    final wrapped =
        texts.singleWhere((text) => text.text.startsWith('Camera was not'));
    final next =
        texts.singleWhere((text) => text.text.startsWith('Subject moved'));
    final oneLine = texts.singleWhere((text) => text.text == 'Process');

    // A wrapped label is taller than a single line and must not run into the
    // next label on the same branch.
    expect(wrapped.text.split('\n'), hasLength(greaterThan(1)));
    expect(wrapped.bounds.height, greaterThan(oneLine.bounds.height));
    expect(wrapped.bounds.bottom, lessThan(next.bounds.top));
  });

  test('wardley renders components and axis stages', () {
    final s = _m.render('''
wardley-beta
title Tea
component Kettle [0.43, 0.35]
component Power [0.10, 0.70]
Kettle -> Power
evolve Kettle 0.62
''');
    expect(_texts(s), containsAll(['Kettle', 'Power', 'Genesis']));
  });

  test('eventmodeling renders typed lanes', () {
    final s = _m.render('''
eventmodeling
tf 01 ui CartUI
tf 02 cmd AddItem
tf 03 evt ItemAdded
tf 04 rmo CartSummary
''');
    // Upstream conceptual swimlanes: UI/Automation, Command/Read Model, Events.
    expect(
      _texts(s),
      containsAll(
        ['CartUI', 'AddItem', 'UI/Automation', 'Command/Read Model'],
      ),
    );

    Rect entityRect(int fill) => (_flat(s.nodes)
            .whereType<SceneShape>()
            .singleWhere((shape) =>
                shape.fill?.color.value == fill &&
                shape.geometry is RectGeometry)
            .geometry as RectGeometry)
        .rect;
    final command = entityRect(0xffbcd6fe);
    final readModel = entityRect(0xffd3f1a2);
    expect(command.right, lessThan(readModel.left),
        reason: 'returning to a populated lane should append after its boxes');
  });

  test('railroad renders rule alternatives', () {
    final s = _m.render('''
railroad-diagram
digit = "0" | "1" | "2" ;
''');
    // Upstream renders the rule name with a trailing ' =' on the rail.
    expect(_texts(s), containsAll(['digit =', '0', '1', '2']));
  });
}
