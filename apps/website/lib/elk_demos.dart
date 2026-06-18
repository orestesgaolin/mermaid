/// Example graphs for the ELK demo page, laid out by the standalone
/// `elk` package (no mermaid) and rendered to inline SVG strings.
///
/// Kept separate from the Jaspr page so the layout + SVG logic is plain,
/// testable Dart; the page injects [ElkDemo.svg] via `raw()`.
library;

import 'package:elk/elk.dart';

/// A titled demo: the explanation plus its rendered SVG. [wide] cards span the
/// full width of the card grid (e.g. the wide left-to-right graph).
class ElkDemo {
  ElkDemo(this.title, this.blurb, this.svg, {this.wide = false});
  final String title;
  final String blurb;
  final String svg;
  final bool wide;
}

/// Builds every demo by laying its graph out with [ElkLayered] and rendering
/// the result to an inline SVG string.
List<ElkDemo> buildElkDemos() {
  return [
    _demo(
      'Branch & merge',
      'A directed graph laid out in layers, top-to-bottom. Note the '
          'right-angle (orthogonal) edge routing — the ELK signature.',
      const ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
        children: [
          ElkNode(id: 'a', width: 110, height: 44),
          ElkNode(id: 'b', width: 110, height: 44),
          ElkNode(id: 'c', width: 110, height: 44),
          ElkNode(id: 'd', width: 110, height: 44),
          ElkNode(id: 'e', width: 110, height: 44),
        ],
        edges: [
          ElkEdge(id: 'e1', sources: ['a'], targets: ['b']),
          ElkEdge(id: 'e2', sources: ['a'], targets: ['c']),
          ElkEdge(id: 'e3', sources: ['b'], targets: ['d']),
          ElkEdge(id: 'e4', sources: ['c'], targets: ['d']),
          ElkEdge(id: 'e5', sources: ['d'], targets: ['e']),
        ],
      ),
      const {'a': 'Start', 'b': 'Build', 'c': 'Test', 'd': 'Merge', 'e': 'Deploy'},
    ),
    _demo(
      'Nested cluster',
      'Compound nodes (clusters) are sized and positioned by the layout; '
          'children stay inside their parent. Edges cross cluster borders '
          'orthogonally.',
      const ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
        children: [
          ElkNode(id: 'in', width: 100, height: 44),
          ElkNode(id: 'pool', children: [
            ElkNode(id: 'w1', width: 100, height: 44),
            ElkNode(id: 'w2', width: 100, height: 44),
          ]),
          ElkNode(id: 'out', width: 100, height: 44),
        ],
        edges: [
          ElkEdge(id: 'e1', sources: ['in'], targets: ['w1']),
          ElkEdge(id: 'e2', sources: ['in'], targets: ['w2']),
          ElkEdge(id: 'e3', sources: ['w1'], targets: ['out']),
          ElkEdge(id: 'e4', sources: ['w2'], targets: ['out']),
        ],
      ),
      const {
        'in': 'Input',
        'pool': 'Worker pool',
        'w1': 'Worker A',
        'w2': 'Worker B',
        'out': 'Output',
      },
    ),
    _demo(
      'Left-to-right dependency graph',
      'The same algorithm with horizontal flow — exactly the shape a package '
          'dependency visualization needs. Each node is a package; edges are '
          '“depends on”.',
      const ElkGraph(
        layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
        children: [
          ElkNode(id: 'app', width: 120, height: 44),
          ElkNode(id: 'ui', width: 120, height: 44),
          ElkNode(id: 'core', width: 120, height: 44),
          ElkNode(id: 'elk', width: 120, height: 44),
          ElkNode(id: 'http', width: 120, height: 44),
          ElkNode(id: 'meta', width: 120, height: 44),
        ],
        edges: [
          ElkEdge(id: 'e1', sources: ['app'], targets: ['ui']),
          ElkEdge(id: 'e2', sources: ['app'], targets: ['core']),
          ElkEdge(id: 'e3', sources: ['ui'], targets: ['core']),
          ElkEdge(id: 'e4', sources: ['core'], targets: ['elk']),
          ElkEdge(id: 'e5', sources: ['core'], targets: ['http']),
          ElkEdge(id: 'e6', sources: ['elk'], targets: ['meta']),
          ElkEdge(id: 'e7', sources: ['http'], targets: ['meta']),
        ],
      ),
      const {
        'app': 'my_app',
        'ui': 'my_app_ui',
        'core': 'my_core',
        'elk': 'elk',
        'http': 'http',
        'meta': 'meta',
      },
      wide: true,
    ),
  ];
}

ElkDemo _demo(
    String title, String blurb, ElkGraph graph, Map<String, String> labels,
    {bool wide = false}) {
  final result = const ElkLayered().layout(graph);
  return ElkDemo(title, blurb, _renderSvg(result, labels), wide: wide);
}

// --- SVG rendering (pure; nodes as rounded rects, clusters as dashed
// containers, edges as orthogonal polylines with arrowheads). ----------------

const _pad = 16.0;
const _nodeFill = '#ececff';
const _nodeStroke = '#9b8fd6';
const _clusterFill = '#f6f4fc';
const _clusterStroke = '#c8bfe8';
const _edgeStroke = '#6b5fb0';

String _renderSvg(ElkResult r, Map<String, String> labels) {
  final w = r.width + _pad * 2;
  final h = r.height + _pad * 2;
  final b = StringBuffer();
  b.writeln('<svg viewBox="0 0 ${_n(w)} ${_n(h)}" '
      'xmlns="http://www.w3.org/2000/svg" class="elk-svg" role="img">');
  b.writeln('<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" '
      'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
      '<path d="M0,0 L10,5 L0,10 z" fill="$_edgeStroke"/></marker></defs>');
  b.writeln('<g transform="translate(${_n(_pad)},${_n(_pad)})">');

  void drawClusters(List<ElkPositionedNode> nodes, double dx, double dy) {
    for (final n in nodes) {
      final ax = n.x + dx, ay = n.y + dy;
      if (n.children.isNotEmpty) {
        b.writeln('<rect x="${_n(ax)}" y="${_n(ay)}" width="${_n(n.width)}" '
            'height="${_n(n.height)}" rx="8" fill="$_clusterFill" '
            'stroke="$_clusterStroke" stroke-dasharray="4 3"/>');
        final label = labels[n.id];
        if (label != null) {
          // Draw the label just above the cluster box so it never overlaps the
          // child nodes inside.
          b.writeln('<text x="${_n(ax + 2)}" y="${_n(ay - 5)}" '
              'class="cluster-label">${_esc(label)}</text>');
        }
        drawClusters(n.children, ax, ay);
      }
    }
  }

  void drawLeaves(List<ElkPositionedNode> nodes, double dx, double dy) {
    for (final n in nodes) {
      final ax = n.x + dx, ay = n.y + dy;
      if (n.children.isNotEmpty) {
        drawLeaves(n.children, ax, ay);
      } else {
        b.writeln('<rect x="${_n(ax)}" y="${_n(ay)}" width="${_n(n.width)}" '
            'height="${_n(n.height)}" rx="6" fill="$_nodeFill" '
            'stroke="$_nodeStroke"/>');
        final label = labels[n.id] ?? n.id;
        b.writeln('<text x="${_n(ax + n.width / 2)}" '
            'y="${_n(ay + n.height / 2)}" class="node-label" '
            'text-anchor="middle" dominant-baseline="central">'
            '${_esc(label)}</text>');
      }
    }
  }

  drawClusters(r.children, 0, 0);
  drawLeaves(r.children, 0, 0);

  for (final e in r.edges) {
    if (e.sections.isEmpty) continue;
    final pts =
        e.sections.first.points.map((p) => '${_n(p.x)},${_n(p.y)}').join(' ');
    b.writeln('<polyline points="$pts" fill="none" stroke="$_edgeStroke" '
        'stroke-width="1.6" marker-end="url(#arrow)"/>');
  }

  b.writeln('</g></svg>');
  return b.toString();
}

String _n(double v) => v.toStringAsFixed(1);
String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
