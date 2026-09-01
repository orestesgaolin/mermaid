import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

const _budgetReviewSource = '''flowchart TD
  entry_0[/"Today tab card tap"/]
  entry_0 -->|"br.proposalAvailable is true"| br_intro
  br_intro["br_intro"]
  br_recent_summary["br_recent_summary"]
  br_activity_rating["br_activity_rating"]
  br_not_sure_1["br_not_sure_1"]
  br_not_sure_2["br_not_sure_2"]
  br_contact_support["br_contact_support"]
  br_not_now_exit(("br_not_now_exit"))
  br_recommendation_summary["br_recommendation_summary"]
  br_recommendation["br_recommendation"]
  br_adjust_budget["br_adjust_budget"]
  br_confirmation["br_confirmation"]
  br_done(("br_done"))
  br_intro -->|"next"| br_recent_summary
  br_recent_summary -->|"next"| br_activity_rating
  br_activity_rating -->|"comfortable (middle cohort) — keep current budget"| br_confirmation
  br_activity_rating -->|"I'm not sure"| br_not_sure_1
  br_activity_rating -->|"above / comfortable / below"| br_recommendation_summary
  br_not_sure_1 -->|"next"| br_not_sure_2
  br_not_sure_2 -->|"contact member support"| br_contact_support
  br_not_sure_2 -->|"not now"| br_not_now_exit
  br_recommendation_summary -->|"current budget still works"| br_confirmation
  br_recommendation_summary -->|"higher / lower recommendation"| br_recommendation
  br_recommendation -->|"adjust manually"| br_adjust_budget
  br_recommendation -->|"set / keep"| br_confirmation
  br_adjust_budget -->|"save adjustment"| br_confirmation
  br_confirmation -->|"done"| br_done''';

void main() {
  testWidgets('long consumer edge label uses painted path arc midpoint', (
    tester,
  ) async {
    final scene = core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(_budgetReviewSource);
    final edge = _findGroup(
      scene.nodes,
      'edge_br_recommendation_summary_br_confirmation_9',
    );
    final label = _findGroup(
      scene.nodes,
      'edgelabel_br_recommendation_summary_br_confirmation_9',
    );
    final path = edge.children
        .whereType<core.SceneShape>()
        .map((shape) => shape.geometry)
        .whereType<core.PathGeometry>()
        .single;
    final expected = _densePathMidpoint(path);
    final actual = core.sceneBounds(label.children)!.center;

    expect(
      _distance(actual, expected),
      lessThan(0.5),
      reason: 'label must follow the final clipped and shortened path',
    );
  });

  testWidgets('midpoint collision adjustment stays clear of nodes', (
    tester,
  ) async {
    final scene = core.Mermaid(
      measurer: const FlutterTextMeasurer(),
    ).render(_budgetReviewSource);
    final edge = _findGroup(
      scene.nodes,
      'edge_br_activity_rating_br_confirmation_3',
    );
    final path = edge.children
        .whereType<core.SceneShape>()
        .map((shape) => shape.geometry)
        .whereType<core.PathGeometry>()
        .single;
    final label = core.sceneBounds(
      _findGroup(
        scene.nodes,
        'edgelabel_br_activity_rating_br_confirmation_3',
      ).children,
    )!;
    final contactSupport = core.sceneBounds(
      _findGroup(scene.nodes, 'br_contact_support').children,
    )!;
    final rawAnchor = _densePathMidpoint(path);
    final rawLabel = core.Rect.fromCenter(rawAnchor, label.width, label.height);
    final displacement = _distance(label.center, rawAnchor);

    expect(_rectsOverlap(rawLabel, contactSupport), isTrue);
    expect(_rectsOverlap(label, contactSupport), isFalse);
    expect(displacement, greaterThan(0));
    expect(displacement, lessThanOrEqualTo(96));
    expect(displacement / 8, closeTo((displacement / 8).round(), 0.001));
  });
}

core.SceneGroup _findGroup(List<core.SceneNode> nodes, String id) {
  for (final node in nodes) {
    if (node is! core.SceneGroup) continue;
    if (node.id == id) return node;
    try {
      return _findGroup(node.children, id);
    } on StateError {
      // Continue with the next sibling.
    }
  }
  throw StateError('No scene group with id $id');
}

/// High-resolution reference independent from the production sample bound.
core.Point _densePathMidpoint(core.PathGeometry path) {
  final segments = <(core.Point, core.Point)>[];
  core.Point? current;
  core.Point? subpathStart;

  void add(core.Point end) {
    final start = current;
    if (start != null && start != end) segments.add((start, end));
    current = end;
  }

  for (final command in path.commands) {
    switch (command) {
      case core.MoveTo(:final p):
        current = p;
        subpathStart = p;
      case core.LineTo(:final p):
        add(p);
      case core.QuadTo(:final c, :final p):
        final start = current!;
        for (var i = 1; i <= 200; i++) {
          final t = i / 200;
          final u = 1 - t;
          add(
            core.Point(
              u * u * start.x + 2 * u * t * c.x + t * t * p.x,
              u * u * start.y + 2 * u * t * c.y + t * t * p.y,
            ),
          );
        }
      case core.CubicTo(:final c1, :final c2, :final p):
        final start = current!;
        for (var i = 1; i <= 200; i++) {
          final t = i / 200;
          final u = 1 - t;
          add(
            core.Point(
              u * u * u * start.x +
                  3 * u * u * t * c1.x +
                  3 * u * t * t * c2.x +
                  t * t * t * p.x,
              u * u * u * start.y +
                  3 * u * u * t * c1.y +
                  3 * u * t * t * c2.y +
                  t * t * t * p.y,
            ),
          );
        }
      case core.ClosePath():
        add(subpathStart!);
    }
  }

  final lengths = <double>[];
  var total = 0.0;
  for (final segment in segments) {
    final length = _distance(segment.$1, segment.$2);
    lengths.add(length);
    total += length;
  }
  final target = total / 2;
  var walked = 0.0;
  for (var i = 0; i < segments.length; i++) {
    final length = lengths[i];
    if (walked + length >= target) {
      final segment = segments[i];
      final t = (target - walked) / length;
      return core.Point(
        segment.$1.x + (segment.$2.x - segment.$1.x) * t,
        segment.$1.y + (segment.$2.y - segment.$1.y) * t,
      );
    }
    walked += length;
  }
  return segments.last.$2;
}

double _distance(core.Point a, core.Point b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  return math.sqrt(dx * dx + dy * dy);
}

bool _rectsOverlap(core.Rect a, core.Rect b) =>
    a.left < b.right &&
    b.left < a.right &&
    a.top < b.bottom &&
    b.top < a.bottom;
