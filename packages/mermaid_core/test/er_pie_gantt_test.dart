/// Parser + layout tests for the ER, pie and gantt diagrams.
library;

import 'package:mermaid_core/src/diagrams/er/er_layout.dart';
import 'package:mermaid_core/src/diagrams/er/er_model.dart';
import 'package:mermaid_core/src/diagrams/er/er_parser.dart';
import 'package:mermaid_core/src/diagrams/gantt/gantt_dates.dart';
import 'package:mermaid_core/src/diagrams/gantt/gantt_layout.dart';
import 'package:mermaid_core/src/diagrams/gantt/gantt_parser.dart';
import 'package:mermaid_core/src/diagrams/pie/pie_layout.dart';
import 'package:mermaid_core/src/diagrams/pie/pie_parser.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

List<SceneNode> flatten(List<SceneNode> nodes) => [
      for (final n in nodes) ...[
        n,
        if (n is SceneGroup) ...flatten(n.children),
      ],
    ];

void main() {
  group('ER parser', () {
    test('symbol relationship with label', () {
      final d = parseErDiagram(
          'erDiagram\nCUSTOMER ||--o{ ORDER : places');
      expect(d.entities.keys, containsAll(['CUSTOMER', 'ORDER']));
      final r = d.relationships.single;
      expect(r.cardFrom, ErCardinality.onlyOne);
      expect(r.cardTo, ErCardinality.zeroOrMore);
      expect(r.identifying, isTrue);
      expect(r.label, 'places');
    });
    test('all cardinality tokens', () {
      final d = parseErDiagram('erDiagram\n'
          'A |o..o| B : a\n'
          'C }|--|{ D : b\n'
          'E }o--o{ F : c');
      expect(d.relationships[0].cardFrom, ErCardinality.zeroOrOne);
      expect(d.relationships[0].cardTo, ErCardinality.zeroOrOne);
      expect(d.relationships[0].identifying, isFalse);
      expect(d.relationships[1].cardFrom, ErCardinality.oneOrMore);
      expect(d.relationships[1].cardTo, ErCardinality.oneOrMore);
      expect(d.relationships[2].cardFrom, ErCardinality.zeroOrMore);
      expect(d.relationships[2].cardTo, ErCardinality.zeroOrMore);
    });
    test('word-form relationship', () {
      final d = parseErDiagram(
          'erDiagram\nMANUFACTURER only one to zero or more CAR : makes');
      final r = d.relationships.single;
      expect(r.cardFrom, ErCardinality.onlyOne);
      expect(r.cardTo, ErCardinality.zeroOrMore);
    });
    test('attributes with keys and comments', () {
      final d = parseErDiagram('erDiagram\nCUSTOMER {\n'
          'string name "the full name"\n'
          'int custNumber PK "unique"\n'
          'string sector FK,UK\n'
          '}');
      final attrs = d.entities['CUSTOMER']!.attributes;
      expect(attrs[0].type, 'string');
      expect(attrs[0].name, 'name');
      expect(attrs[0].comment, 'the full name');
      expect(attrs[1].keys, ['PK']);
      expect(attrs[2].keys, ['FK', 'UK']);
    });
    test('entity alias', () {
      final d = parseErDiagram('erDiagram\np[Person]\np ||--o| h : owns');
      expect(d.entities['p']!.label, 'Person');
    });
    test('quoted entity names', () {
      final d =
          parseErDiagram('erDiagram\n"Order Line" }|--|| ORDER : belongs');
      expect(d.entities.keys, contains('Order Line'));
    });
    test('garbage throws', () {
      expect(() => parseErDiagram('erDiagram\n!!!'),
          throwsA(isA<MermaidParseException>()));
    });
  });

  group('ER layout', () {
    test('entity table with header and rows, crow feet rendered', () {
      final scene = layoutErDiagram(
        parseErDiagram('erDiagram\n'
            'CUSTOMER ||--o{ ORDER : places\n'
            'CUSTOMER {\nstring name PK\nint age\n}'),
        measurer: measurer,
        theme: theme,
      );
      final texts = flatten(scene.nodes).whereType<SceneText>().map((t) => t.text);
      expect(texts, containsAll(['CUSTOMER', 'ORDER', 'name', 'age', 'places']));
      // Crow's foot: at least one circle marker (zero side) present.
      expect(
        flatten(scene.nodes)
            .whereType<SceneShape>()
            .any((s) => s.geometry is CircleGeometry),
        isTrue,
      );
      expect(scene.size.width, greaterThan(0));
    });
    test('non-identifying relationship is dashed', () {
      final scene = layoutErDiagram(
        parseErDiagram('erDiagram\nA |o..o| B : maybe'),
        measurer: measurer,
        theme: theme,
      );
      expect(
        flatten(scene.nodes).whereType<SceneShape>().any(
            (s) => s.geometry is PathGeometry && s.stroke?.dash != null),
        isTrue,
      );
    });
  });

  group('pie parser', () {
    test('title and slices', () {
      final p = parsePieChart(
          'pie title Pets\n"Dogs" : 386\n"Cats" : 85.9');
      expect(p.title, 'Pets');
      expect(p.slices.length, 2);
      expect(p.slices[0].label, 'Dogs');
      expect(p.slices[1].value, 85.9);
    });
    test('showData flag', () {
      expect(parsePieChart('pie showData\n"A" : 1').showData, isTrue);
    });
    test('invalid value throws', () {
      expect(() => parsePieChart('pie\n"A" : abc'),
          throwsA(isA<MermaidParseException>()));
    });
  });

  group('pie layout', () {
    test('slices sum to full circle with legend and percentages', () {
      final scene = layoutPieChart(
        parsePieChart('pie title P\n"A" : 75\n"B" : 25'),
        measurer: measurer,
        theme: theme,
      );
      final texts =
          flatten(scene.nodes).whereType<SceneText>().map((t) => t.text).toList();
      expect(texts, containsAll(['A', 'B', '75%', '25%', 'P']));
      expect(
          flatten(scene.nodes).whereType<SceneGroup>().where(
              (g) => (g.id ?? '').startsWith('slice_')),
          hasLength(2));
    });
  });

  group('gantt dates', () {
    test('parse YYYY-MM-DD', () {
      expect(parseGanttDate('2014-01-06', 'YYYY-MM-DD'),
          DateTime(2014, 1, 6));
    });
    test('parse with time', () {
      expect(parseGanttDate('2014-01-06 13:30', 'YYYY-MM-DD HH:mm'),
          DateTime(2014, 1, 6, 13, 30));
    });
    test('mismatch returns null', () {
      expect(parseGanttDate('06/01/2014', 'YYYY-MM-DD'), isNull);
    });
    test('durations', () {
      expect(parseGanttDuration('2d'), const Duration(days: 2));
      expect(parseGanttDuration('1w'), const Duration(days: 7));
      expect(parseGanttDuration('90m'), const Duration(minutes: 90));
    });
    test('axis formatting', () {
      expect(formatGanttDate(DateTime(2014, 1, 6), '%Y-%m-%d'), '2014-01-06');
      expect(formatGanttDate(DateTime(2014, 1, 6), '%b %e'), 'Jan 6');
    });
  });

  group('gantt parser', () {
    test('sections, tags, ids, explicit dates and durations', () {
      final g = parseGanttChart('''
gantt
    dateFormat YYYY-MM-DD
    title Plan
    section Design
    Mockups : done, des1, 2014-01-06, 2014-01-08
    Review  : active, des2, 2014-01-09, 3d
    section Build
    Code    : crit, after des2, 5d
    Ship    : milestone, 2014-01-25, 1d
''');
      expect(g.title, 'Plan');
      expect(g.sections.map((s) => s.name), ['Design', 'Build']);
      final mockups = g.sections[0].tasks[0];
      expect(mockups.done, isTrue);
      expect(mockups.start, DateTime(2014, 1, 6));
      expect(mockups.end, DateTime(2014, 1, 8));
      final review = g.sections[0].tasks[1];
      expect(review.active, isTrue);
      expect(review.end, DateTime(2014, 1, 12));
      final code = g.sections[1].tasks[0];
      expect(code.crit, isTrue);
      expect(code.start, review.end);
      expect(code.end, review.end.add(const Duration(days: 5)));
      final ship = g.sections[1].tasks[1];
      expect(ship.milestone, isTrue);
      expect(ship.start, ship.end);
    });
    test('task without start chains after previous', () {
      final g = parseGanttChart('gantt\ndateFormat YYYY-MM-DD\n'
          'A : 2024-01-01, 2d\nB : 3d');
      expect(g.sections[0].tasks[1].start, DateTime(2024, 1, 3));
      expect(g.sections[0].tasks[1].end, DateTime(2024, 1, 6));
    });
  });

  group('gantt layout', () {
    test('bars positioned by time, axis labels present', () {
      final scene = layoutGanttChart(
        parseGanttChart('gantt\ndateFormat YYYY-MM-DD\ntitle T\n'
            'section S\nA : a1, 2024-01-01, 2d\nB : after a1, 2d'),
        measurer: measurer,
        theme: theme,
      );
      Rect barOf(String id) {
        final g = flatten(scene.nodes)
            .whereType<SceneGroup>()
            .firstWhere((g) => g.id == id);
        final shape = flatten(g.children)
            .whereType<SceneShape>()
            .firstWhere((s) => s.geometry is RectGeometry);
        return (shape.geometry as RectGeometry).rect;
      }

      final a = barOf('a1');
      final b = barOf('task0');
      expect(b.left, closeTo(a.right, 2));
      expect(b.top, greaterThan(a.top));
      // Axis tick labels exist (formatted dates).
      expect(
        flatten(scene.nodes)
            .whereType<SceneText>()
            .any((t) => RegExp(r'^\d{2}-\d{2}$').hasMatch(t.text)),
        isTrue,
      );
    });
    test('milestone renders a diamond', () {
      final scene = layoutGanttChart(
        parseGanttChart('gantt\ndateFormat YYYY-MM-DD\n'
            'M : milestone, 2024-01-05, 1d'),
        measurer: measurer,
        theme: theme,
      );
      expect(
        flatten(scene.nodes)
            .whereType<SceneShape>()
            .any((s) => s.geometry is PolygonGeometry),
        isTrue,
      );
    });
  });
}
