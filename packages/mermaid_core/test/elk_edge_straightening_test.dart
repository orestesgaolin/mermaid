/// ELK edge clean-up after layout: mermaid 12's `elk.straightenEdges` (#93).
library;

import 'package:mermaid_core/mermaid_core.dart';
import 'package:mermaid_core/src/diagrams/flowchart/elk_adapter.dart';
import 'package:test/test.dart';

import 'support/scene.dart';

const _mermaid = Mermaid(measurer: ApproximateTextMeasurer());

const _diagram = '''
flowchart TD
    subgraph boot["Bootstrap"]
        launcher
        launcher_kiosk
        pick_venue
    end
    subgraph west["West zone"]
        west_core
    end
    subgraph east["East zone"]
        east_core
    end
    gw
    stream
    ident
    launcher --> east_core
    launcher --> west_core
    launcher_kiosk --> east_core
    launcher_kiosk --> west_core
    east_core --> ident
    east_core --> pick_venue
    east_core --> stream
    west_core --> gw
    west_core --> ident
    west_core --> pick_venue
    west_core --> stream
''';

String _source({bool? straighten}) {
  final config = straighten == null
      ? 'config:\n  layout: elk\n'
      : 'config:\n  layout: elk\n  elk:\n    straightenEdges: $straighten\n';
  return '---\n$config---\n$_diagram';
}

/// Edge polylines (move/line points of each edge stroke), by edge group id.
Map<String, List<Point>> _routes(RenderScene scene) => {
  for (final group in groupsOf(scene.nodes))
    if ((group.id ?? '').startsWith('edge_'))
      group.id!: [
        for (final shape in group.children.whereType<SceneShape>())
          if (shape.paintRole == ScenePaintRole.edgeStroke)
            ...edgeRoute((shape.geometry as PathGeometry).commands),
      ],
};

bool _vertical(Point a, Point b) => (a.x - b.x).abs() < 0.01;

/// The bends of a route: points the edge passes straight through are dropped.
List<Point> _bends(List<Point> pts) {
  final out = <Point>[];
  for (final p in pts) {
    if (out.isNotEmpty && out.last.distanceTo(p) < 0.01) continue;
    if (out.length >= 2 &&
        _vertical(out[out.length - 2], out.last) == _vertical(out.last, p)) {
      out.removeLast();
    }
    out.add(p);
  }
  return out;
}

/// A short terminal jog: the first (or last) segment runs at most 30 px, then
/// steps aside by at most 16 px and continues in the same direction until a
/// later bend, which can absorb the step.
bool _hasTerminalJog(List<Point> route) {
  final pts = _bends(route);
  bool front(List<Point> p) {
    if (p.length < 5) return false;
    final v = _vertical(p[0], p[1]);
    if (v != _vertical(p[2], p[3]) || v == _vertical(p[1], p[2])) return false;
    final jog = v ? (p[2].x - p[1].x).abs() : (p[2].y - p[1].y).abs();
    if (p[0].distanceTo(p[1]) > 30 || jog <= 0.01 || jog > 16) return false;
    var last = 3;
    while (last + 1 < p.length && _vertical(p[last], p[last + 1]) == v) {
      last++;
    }
    return last < p.length - 1;
  }

  return front(pts) || front(pts.reversed.toList());
}

void main() {
  group('elk.straightenEdges', () {
    test('ELK leaves short terminal jogs when it is off', () {
      final routes = _routes(_mermaid.render(_source(straighten: false)));
      expect(routes.values.where(_hasTerminalJog), isNotEmpty);
    });

    test('removes short terminal jogs by default', () {
      final routes = _routes(_mermaid.render(_source()));
      expect(routes, hasLength(11));
      for (final MapEntry(:key, :value) in routes.entries) {
        expect(_hasTerminalJog(value), isFalse, reason: '$key: $value');
      }
    });

    test('keeps every other bend of the route', () {
      final before = _routes(_mermaid.render(_source(straighten: false)));
      final after = _routes(_mermaid.render(_source(straighten: true)));
      for (final id in before.keys) {
        final removed = _bends(before[id]!).length - _bends(after[id]!).length;
        expect(removed, anyOf(0, 2, 4), reason: id);
        expect(after[id]!.first.y, before[id]!.first.y, reason: id);
        expect(after[id]!.last, before[id]!.last, reason: id);
      }
    });
  });
  group('straightenEdgeTerminals', () {
    // Leaves (0,0) downward, steps 10 px right after 20 px, then turns
    // towards (100,100) and drops into the target.
    List<Point> jogged() => const [
      Point(0, 0),
      Point(0, 20),
      Point(10, 20),
      Point(10, 60),
      Point(100, 60),
      Point(100, 100),
    ];

    test('moves the run after the jog onto the first segment', () {
      final routes = {'e0': jogged()};
      straightenEdgeTerminals(routes, {}, {});
      expect(routes['e0'], const [
        Point(0, 0),
        Point(0, 60),
        Point(100, 60),
        Point(100, 100),
      ]);
    });

    test('moves the label with the run', () {
      final routes = {'e0': jogged()};
      final labels = {'e0': const Point(10, 40)};
      straightenEdgeTerminals(routes, labels, {'e0': const Size(8, 8)});
      expect(labels['e0'], const Point(0, 40));
    });

    test('keeps the jog when straightening adds a crossing', () {
      final routes = {
        'e0': jogged(),
        'e1': const [Point(-20, 40), Point(5, 40)],
      };
      straightenEdgeTerminals(routes, {}, {});
      expect(routes['e0'], jogged());
    });

    test('keeps the jog when the label would cover another edge', () {
      final routes = {
        'e0': jogged(),
        'e1': const [Point(-3, 30), Point(-3, 50)],
      };
      final labels = {'e0': const Point(10, 40)};
      straightenEdgeTerminals(routes, labels, {'e0': const Size(8, 8)});
      expect(routes['e0'], jogged());
      expect(labels['e0'], const Point(10, 40));
    });

    test('keeps a jog longer than 16 px', () {
      const route = [
        Point(0, 0),
        Point(0, 20),
        Point(30, 20),
        Point(30, 60),
        Point(100, 60),
        Point(100, 100),
      ];
      final routes = {'e0': route};
      straightenEdgeTerminals(routes, {}, {});
      expect(routes['e0'], route);
    });
  });
}
