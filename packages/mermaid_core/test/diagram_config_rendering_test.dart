import 'dart:convert';
import 'dart:math' as math;

import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());

Iterable<({String form, String source})> _configuredSources(
  String diagramKey,
  Map<String, Object?> values,
  String body,
) sync* {
  yield (
    form: 'init',
    source: '%%{init: ${jsonEncode({diagramKey: values})}}%%\n$body',
  );
  final yaml = values.entries
      .map((entry) => '    ${entry.key}: ${jsonEncode(entry.value)}')
      .join('\n');
  yield (
    form: 'frontmatter',
    source: '---\nconfig:\n  $diagramKey:\n$yaml\n---\n$body',
  );
}

Iterable<({String form, String source})> _configuredElkSources(
  String diagramKey,
  Map<String, Object?> values,
  String body,
) sync* {
  for (final configured in _configuredSources(diagramKey, values, body)) {
    yield (
      form: configured.form,
      source: configured.form == 'init'
          ? configured.source.replaceFirst(
              '{"$diagramKey":',
              '{"layout":"elk","$diagramKey":',
            )
          : configured.source.replaceFirst(
              'config:\n',
              'config:\n  layout: elk\n',
            ),
    );
  }
}

List<SceneNode> _flatten(Iterable<SceneNode> nodes) => [
  for (final node in nodes) ...[
    node,
    if (node is SceneGroup) ..._flatten(node.children),
  ],
];

SceneGroup _group(RenderScene scene, String id) => _flatten(
  scene.nodes,
).whereType<SceneGroup>().singleWhere((group) => group.id == id);

Rect _groupBounds(RenderScene scene, String id) {
  final group = _group(scene, id);
  Rect? bounds;
  for (final node in _flatten(group.children)) {
    final nodeBounds = switch (node) {
      SceneText(:final bounds) => bounds,
      SceneShape(:final geometry) => geometryBounds(geometry),
      _ => null,
    };
    if (nodeBounds != null) {
      bounds = bounds == null ? nodeBounds : bounds.union(nodeBounds);
    }
  }
  return bounds!;
}

SceneText _text(RenderScene scene, String text) => _flatten(
  scene.nodes,
).whereType<SceneText>().singleWhere((node) => node.text == text);

void main() {
  group('per-diagram config renders through init and frontmatter', () {
    test('sequence changes actors, wrapping, alignment, and numbering', () {
      const body = '''
sequenceDiagram
participant A as Alpha
participant B as Beta
activate B
A->>B: This is a long message that must wrap across several lines
Note over A,B: A note
deactivate B
''';
      final values = <String, Object?>{
        'activationWidth': 18,
        'diagramMarginX': 6,
        'diagramMarginY': 4,
        'actorMargin': 80,
        'width': 110,
        'height': 44,
        'boxMargin': 3,
        'boxTextMargin': 2,
        'noteMargin': 4,
        'messageMargin': 12,
        'messageAlign': 'left',
        'noteAlign': 'right',
        'mirrorActors': false,
        'showSequenceNumbers': true,
        'wrap': true,
        'wrapPadding': 3,
      };

      for (final configured in _configuredSources('sequence', values, body)) {
        final scene = _renderer.render(configured.source);
        expect(
          _flatten(scene.nodes).whereType<SceneGroup>().where(
            (group) => group.id == 'actor_A_bottom',
          ),
          isEmpty,
          reason: configured.form,
        );
        expect(
          _text(scene, 'Alpha').bounds.height,
          lessThan(44),
          reason: configured.form,
        );
        expect(
          _flatten(
            scene.nodes,
          ).whereType<SceneText>().any((text) => text.text == '1'),
          isTrue,
          reason: configured.form,
        );
        expect(
          _flatten(scene.nodes)
              .whereType<SceneText>()
              .singleWhere((text) => text.text.startsWith('This is a long'))
              .text,
          contains('\n'),
          reason: configured.form,
        );
        final activation = _flatten(scene.nodes)
            .whereType<SceneShape>()
            .map((shape) => shape.geometry)
            .whereType<RectGeometry>()
            .where((geometry) => (geometry.rect.width - 18).abs() < 0.01);
        expect(activation, isNotEmpty, reason: configured.form);

        final messageGroup = _group(scene, 'msg_A_B');
        final messageText = _flatten(messageGroup.children)
            .whereType<SceneText>()
            .singleWhere((text) => text.text.startsWith('This is a'));
        final messagePath = _flatten(messageGroup.children)
            .whereType<SceneShape>()
            .map((shape) => shape.geometry)
            .whereType<PathGeometry>()
            .first;
        final messageXs = <double>[
          for (final command in messagePath.commands)
            ...switch (command) {
              MoveTo(:final p) || LineTo(:final p) => [p.x],
              _ => const <double>[],
            },
        ];
        expect(
          messageText.bounds.left,
          closeTo(messageXs.reduce(math.min) + 4, 0.01),
          reason: configured.form,
        );

        final note = _group(scene, 'note');
        final noteRect = _flatten(note.children)
            .whereType<SceneShape>()
            .map((shape) => shape.geometry)
            .whereType<RectGeometry>()
            .single
            .rect;
        final noteText = _flatten(note.children).whereType<SceneText>().single;
        expect(
          noteText.bounds.right,
          closeTo(noteRect.right - 4, 0.01),
          reason: configured.form,
        );
      }
    });

    test('sequence explicit nowrap overrides config wrap', () {
      const body = '''
sequenceDiagram
A->>B: nowrap: This long message stays on one line despite global wrapping
''';
      for (final configured in _configuredSources('sequence', const {
        'wrap': true,
        'width': 80,
      }, body)) {
        final message = _flatten(_renderer.render(configured.source).nodes)
            .whereType<SceneText>()
            .singleWhere((text) => text.text.startsWith('This long message'));
        expect(message.text, isNot(contains('\n')), reason: configured.form);
      }
    });

    test('sequence config numbering survives autonumber off', () {
      const body = '''
sequenceDiagram
A->>B: first
autonumber off
A->>B: second
''';
      for (final configured in _configuredSources('sequence', const {
        'showSequenceNumbers': true,
      }, body)) {
        final numbers = _flatten(
          _renderer.render(configured.source).nodes,
        ).whereType<SceneText>().map((text) => text.text);
        expect(numbers, containsAll(['1', '2']), reason: configured.form);
      }
    });

    test('flowchart changes spacing, node padding, wrapping, and curve', () {
      const body = '''
flowchart TB
  A[This is a deliberately long node label] --> B[Beta]
  A --> C[Gamma]
''';
      final baseline = _renderer.render(body);
      for (final configured in _configuredSources('flowchart', const {
        'nodeSpacing': 140,
        'rankSpacing': 120,
        'curve': 'linear',
        'padding': 2,
        'wrappingWidth': 60,
      }, body)) {
        final scene = _renderer.render(configured.source);
        expect(
          (_groupBounds(scene, 'B').center.x -
                  _groupBounds(scene, 'C').center.x)
              .abs(),
          greaterThan(
            (_groupBounds(baseline, 'B').center.x -
                    _groupBounds(baseline, 'C').center.x)
                .abs(),
          ),
          reason: configured.form,
        );
        expect(
          (_groupBounds(scene, 'A').center.y -
                  _groupBounds(scene, 'B').center.y)
              .abs(),
          greaterThan(
            (_groupBounds(baseline, 'A').center.y -
                    _groupBounds(baseline, 'B').center.y)
                .abs(),
          ),
          reason: configured.form,
        );
        final wrapped = _flatten(scene.nodes)
            .whereType<SceneText>()
            .singleWhere((text) => text.text.contains('deliberately'));
        final baselineLabel = _flatten(baseline.nodes)
            .whereType<SceneText>()
            .singleWhere((text) => text.text.contains('deliberately'));
        expect(
          wrapped.text.split('\n').length,
          greaterThan(baselineLabel.text.split('\n').length),
          reason: configured.form,
        );
        expect(
          _groupBounds(scene, 'B').height,
          lessThan(_groupBounds(baseline, 'B').height),
          reason: configured.form,
        );
        final edgePaths = _flatten(scene.nodes)
            .whereType<SceneGroup>()
            .where((group) => group.role == SceneGroupRole.edge)
            .expand((group) => _flatten(group.children))
            .whereType<SceneShape>()
            .map((shape) => shape.geometry)
            .whereType<PathGeometry>();
        expect(
          edgePaths.every((path) => path.commands.whereType<CubicTo>().isEmpty),
          isTrue,
          reason: configured.form,
        );
      }
    });

    test('state changes node padding and both dagre spacings', () {
      const body = '''
stateDiagram-v2
[*] --> A
[*] --> B
A --> C
B --> C
''';
      final baseline = _renderer.render(body);
      for (final configured in _configuredSources('state', const {
        'padding': 2,
        'nodeSpacing': 140,
        'rankSpacing': 120,
      }, body)) {
        final scene = _renderer.render(configured.source);
        expect(
          scene.size.width,
          greaterThan(baseline.size.width),
          reason: configured.form,
        );
        expect(
          scene.size.height,
          greaterThan(baseline.size.height),
          reason: configured.form,
        );
        expect(
          _groupBounds(scene, 'A').height,
          lessThan(_groupBounds(baseline, 'A').height),
          reason: configured.form,
        );
      }
    });

    test('flowchart and state spacing reaches ELK', () {
      const flowBody = 'flowchart TB\nA --> B\nA --> C';
      const stateBody = 'stateDiagram-v2\nA --> B\nA --> C';
      for (final diagram in [
        (key: 'flowchart', body: flowBody),
        (key: 'state', body: stateBody),
      ]) {
        final compact = _configuredElkSources(diagram.key, const {
          'nodeSpacing': 5,
          'rankSpacing': 5,
        }, diagram.body).toList();
        final spacious = _configuredElkSources(diagram.key, const {
          'nodeSpacing': 120,
          'rankSpacing': 120,
        }, diagram.body).toList();
        for (var i = 0; i < compact.length; i++) {
          final compactScene = _renderer.render(compact[i].source);
          final spaciousScene = _renderer.render(spacious[i].source);
          expect(
            spaciousScene.size.width,
            greaterThan(compactScene.size.width),
            reason: '${diagram.key} ${compact[i].form} nodeSpacing',
          );
          expect(
            spaciousScene.size.height,
            greaterThan(compactScene.size.height),
            reason: '${diagram.key} ${compact[i].form} rankSpacing',
          );
        }
      }
    });

    test('class changes box padding and both dagre spacings', () {
      const body = '''
classDiagram
class A
class B
class C
A <|-- B
A <|-- C
''';
      final baseline = _renderer.render(body);
      for (final configured in _configuredSources('class', const {
        'padding': 2,
        'nodeSpacing': 140,
        'rankSpacing': 120,
      }, body)) {
        final scene = _renderer.render(configured.source);
        expect(
          (_groupBounds(scene, 'B').center.x -
                  _groupBounds(scene, 'C').center.x)
              .abs(),
          greaterThan(
            (_groupBounds(baseline, 'B').center.x -
                    _groupBounds(baseline, 'C').center.x)
                .abs(),
          ),
          reason: configured.form,
        );
        expect(
          (_groupBounds(scene, 'A').center.y -
                  _groupBounds(scene, 'B').center.y)
              .abs(),
          greaterThan(
            (_groupBounds(baseline, 'A').center.y -
                    _groupBounds(baseline, 'B').center.y)
                .abs(),
          ),
          reason: configured.form,
        );
        expect(
          _groupBounds(scene, 'A').height,
          lessThan(_groupBounds(baseline, 'A').height),
          reason: configured.form,
        );
      }
    });

    test('gantt changes bars, tick interval, format, and top axis', () {
      const body = '''
gantt
dateFormat YYYY-MM-DD
title Plan
section Work
First : a, 2024-01-01, 2d
Second : b, after a, 4d
''';
      for (final configured in _configuredSources('gantt', const {
        'barHeight': 30,
        'barGap': 9,
        'axisFormat': '%m/%d',
        'tickInterval': '2day',
        'topAxis': true,
      }, body)) {
        final scene = _renderer.render(configured.source);
        Rect bar(String id) => _flatten(_group(scene, id).children)
            .whereType<SceneShape>()
            .map((shape) => shape.geometry)
            .whereType<RectGeometry>()
            .first
            .rect;
        expect(bar('a').height, 30, reason: configured.form);
        expect(bar('b').top - bar('a').top, 39, reason: configured.form);
        final labels = _flatten(scene.nodes)
            .whereType<SceneText>()
            .map((text) => text.text)
            .where((text) => RegExp(r'^\d{2}/\d{2}$').hasMatch(text))
            .toList();
        expect(labels.length, 6, reason: configured.form);
        final distinctLabels = labels.toSet().toList()..sort();
        expect(distinctLabels, hasLength(3), reason: configured.form);
        for (final label in distinctLabels) {
          expect(
            labels.where((value) => value == label),
            hasLength(2),
            reason: '${configured.form} topAxis $label',
          );
        }
        DateTime dateOf(String label) => DateTime(
          2024,
          int.parse(label.substring(0, 2)),
          int.parse(label.substring(3, 5)),
        );
        expect(
          dateOf(distinctLabels[1]).difference(dateOf(distinctLabels[0])),
          const Duration(days: 2),
          reason: configured.form,
        );
        final title = _text(scene, 'Plan');
        final topAxisLabel = _flatten(scene.nodes)
            .whereType<SceneText>()
            .where((text) => RegExp(r'^\d{2}/\d{2}$').hasMatch(text.text))
            .reduce((a, b) => a.bounds.top < b.bounds.top ? a : b);
        expect(
          title.bounds.bottom,
          lessThanOrEqualTo(topAxisLabel.bounds.top),
          reason: configured.form,
        );
      }
    });

    test('gantt month ticks use calendar boundaries', () {
      const body = '''
gantt
dateFormat YYYY-MM-DD
Start : a, 2024-01-31, 60d
''';
      for (final configured in _configuredSources('gantt', const {
        'axisFormat': '%m/%d',
        'tickInterval': '1month',
      }, body)) {
        final labels = _flatten(
          _renderer.render(configured.source).nodes,
        ).whereType<SceneText>().map((text) => text.text);
        expect(
          labels,
          containsAll(['02/01', '03/01']),
          reason: configured.form,
        );
        expect(labels, isNot(contains('03/02')), reason: configured.form);
      }
    });

    test('pie changes label radius, donut geometry, and legend position', () {
      const body = 'pie\n"A" : 75\n"B" : 25';
      for (final configured in _configuredSources('pie', const {
        'textPosition': 0.2,
        'donutHole': 0.5,
        'legendPosition': 'bottom',
      }, body)) {
        final scene = _renderer.render(configured.source);
        final outer = _flatten(scene.nodes)
            .whereType<SceneShape>()
            .map((shape) => shape.geometry)
            .whereType<CircleGeometry>()
            .single;
        final label = _text(scene, '75%');
        final distance = math.sqrt(
          math.pow(label.bounds.center.x - outer.center.x, 2) +
              math.pow(label.bounds.center.y - outer.center.y, 2),
        );
        expect(distance, closeTo(37, 0.01), reason: configured.form);
        final slice = _flatten(
          _group(scene, 'slice_0').children,
        ).whereType<SceneShape>().single;
        final path = slice.geometry as PathGeometry;
        expect(
          (path.commands.first as MoveTo).p,
          isNot(outer.center),
          reason: configured.form,
        );
        expect(
          path.commands.whereType<CubicTo>().length,
          greaterThanOrEqualTo(6),
          reason: configured.form,
        );
        expect(
          _groupBounds(scene, 'legend_0').top,
          greaterThan(outer.center.y),
          reason: configured.form,
        );
      }
    });

    test(
      'gitGraph changes labels, lanes, parallel positions, and main name',
      () {
        const body = '''
gitGraph
commit id: root
branch left
commit id: left1
checkout trunk
branch right
commit id: right1
''';
        for (final configured in _configuredSources('gitGraph', const {
          'showBranches': true,
          'showCommitLabel': true,
          'rotateCommitLabel': false,
          'parallelCommits': true,
          'mainBranchName': 'trunk',
        }, body)) {
          final scene = _renderer.render(configured.source);
          final texts = _flatten(scene.nodes).whereType<SceneText>().toList();
          expect(
            texts.any((text) => text.text == 'trunk'),
            isTrue,
            reason: configured.form,
          );
          expect(
            texts.any((text) => text.text == 'main'),
            isFalse,
            reason: configured.form,
          );
          expect(_text(scene, 'root').rotation, 0, reason: configured.form);
          expect(
            _groupBounds(scene, 'commit_left1').center.x,
            closeTo(_groupBounds(scene, 'commit_right1').center.x, 0.01),
            reason: configured.form,
          );
        }
      },
    );

    test('gitGraph can hide branch and commit labels', () {
      const body = 'gitGraph\ncommit id: visible';
      for (final configured in _configuredSources('gitGraph', const {
        'showBranches': false,
        'showCommitLabel': false,
      }, body)) {
        final scene = _renderer.render(configured.source);
        final texts = _flatten(scene.nodes).whereType<SceneText>();
        expect(texts, isEmpty, reason: configured.form);
        expect(
          _flatten(scene.nodes).whereType<SceneShape>().where(
            (shape) => shape.geometry is PathGeometry,
          ),
          isEmpty,
          reason: configured.form,
        );
      }
    });

    test('gitGraph can explicitly rotate TB commit labels', () {
      const body = 'gitGraph TB:\ncommit id: rotated';
      final rotated = _configuredSources('gitGraph', const {
        'rotateCommitLabel': true,
      }, body).toList();
      final straight = _configuredSources('gitGraph', const {
        'rotateCommitLabel': false,
      }, body).toList();
      for (var i = 0; i < rotated.length; i++) {
        expect(
          _text(_renderer.render(rotated[i].source), 'rotated').rotation,
          -45,
          reason: rotated[i].form,
        );
        expect(
          _text(_renderer.render(straight[i].source), 'rotated').rotation,
          0,
          reason: straight[i].form,
        );
      }
    });
  });
}
