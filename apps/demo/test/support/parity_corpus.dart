/// The shared parity review corpus: curated `mermaid_samples` cases plus the
/// largest checked-in upstream fixture for each covered diagram family.
///
/// Two entry points read this list:
///
/// * `apps/demo/test/render_corpus_smoke_test.dart` renders every case and
///   asserts nothing throws (runs on every `flutter test`).
/// * `apps/demo/tool/parity_review_test.dart` rasterizes the same cases into
///   `build/parity_review` for the local visual review (opt-in).
library;

import 'dart:io';

import 'package:mermaid_samples/mermaid_samples.dart';

/// Curated samples for the newer diagram types, which have no upstream
/// fixtures checked in.
const curatedParityIds = <String>[
  'subgraphs',
  'math',
  'block',
  'architecture',
  'kanban',
  'cynefin',
  'ishikawa',
  'eventmodeling',
  'railroad',
  'radar',
  'treemap',
  'venn',
  'wardley',
  'handdrawn',
];

/// The largest checked-in upstream fixture for each covered diagram family.
/// Together with the curated cases above this gives a broad, deliberately
/// complex batch without asking a reviewer to inspect all 220 cases.
const parityFixturePaths = <String>[
  'packages/mermaid_core/test/fixtures/upstream_c4/05.mmd',
  'packages/mermaid_core/test/fixtures/upstream_class/11.mmd',
  'packages/mermaid_core/test/fixtures/upstream_er/03.mmd',
  'packages/mermaid_core/test/fixtures/upstream_flowcharts/07.mmd',
  'packages/mermaid_core/test/fixtures/upstream_gantt/08.mmd',
  'packages/mermaid_core/test/fixtures/upstream_git/33.mmd',
  'packages/mermaid_core/test/fixtures/upstream_journey/01.mmd',
  'packages/mermaid_core/test/fixtures/upstream_mindmap/01.mmd',
  'packages/mermaid_core/test/fixtures/upstream_packet/03.mmd',
  'packages/mermaid_core/test/fixtures/upstream_pie/01.mmd',
  'packages/mermaid_core/test/fixtures/upstream_quadrant/02.mmd',
  'packages/mermaid_core/test/fixtures/upstream_requirement/02.mmd',
  'packages/mermaid_core/test/fixtures/upstream_sankey/03.mmd',
  'packages/mermaid_core/test/fixtures/upstream_sequence/01.mmd',
  'packages/mermaid_core/test/fixtures/upstream_state/05.mmd',
  'packages/mermaid_core/test/fixtures/upstream_timeline/03.mmd',
  'packages/mermaid_core/test/fixtures/upstream_xychart/18.mmd',
];

/// One reviewable diagram source with the metadata the report needs.
class ParityCase {
  const ParityCase({
    required this.id,
    required this.title,
    required this.family,
    required this.origin,
    required this.source,
  });

  final String id;
  final String title;
  final String family;
  final String origin;
  final String source;
}

/// Loads every curated sample and upstream fixture, resolved against [root]
/// (the workspace root, see `workspace.dart`).
List<ParityCase> loadParityCases(Directory root) {
  final result = <ParityCase>[];
  for (final id in curatedParityIds) {
    final sample = samples.singleWhere((sample) => sample.id == id);
    result.add(
      ParityCase(
        id: 'curated-$id',
        title: sample.name,
        family: id,
        origin: 'packages/mermaid_samples:$id',
        source: sample.source.trim(),
      ),
    );
  }
  for (final path in parityFixturePaths) {
    final file = File('${root.path}/$path');
    if (!file.existsSync()) {
      throw StateError('Missing parity fixture: ${file.path}');
    }
    final directory = file.parent.path.split('/').last;
    final family = directory.replaceFirst('upstream_', '');
    final fixture = file.uri.pathSegments.last.replaceFirst('.mmd', '');
    result.add(
      ParityCase(
        id: 'upstream-$family-$fixture',
        title: '${_titleCase(family)} fixture $fixture',
        family: family,
        origin: path,
        source: file.readAsStringSync().trim(),
      ),
    );
  }
  return result;
}

String _titleCase(String value) => value
    .split(RegExp(r'[_-]'))
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
