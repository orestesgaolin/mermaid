/// Example graphs for the ELK demo page, laid out by the standalone
/// `elk` package (no mermaid) and rendered to inline SVG strings.
///
/// Kept separate from the Jaspr page so the layout + SVG logic is plain,
/// testable Dart; the page injects [ElkDemo.svg] via `raw()`.
library;

import 'package:elk/elk.dart';

import 'elk_stress_examples.dart';

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
      const {
        'a': 'Start',
        'b': 'Build',
        'c': 'Test',
        'd': 'Merge',
        'e': 'Deploy',
      },
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
          ElkNode(
            id: 'pool',
            children: [
              ElkNode(id: 'w1', width: 100, height: 44),
              ElkNode(id: 'w2', width: 100, height: 44),
            ],
          ),
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
    for (final example in elkStressExamples)
      _demo(
        example.title,
        example.description,
        example.graph,
        example.labels,
        wide: example.wide,
      ),
  ];
}

ElkDemo _demo(
  String title,
  String blurb,
  ElkGraph graph,
  Map<String, String> labels, {
  bool wide = false,
}) {
  final result = const ElkLayered().layout(graph);
  return ElkDemo(
    title,
    blurb,
    _renderSvg(result, graph, labels, title),
    wide: wide,
  );
}

// --- SVG rendering (pure; nodes as rounded rects, clusters as dashed
// containers, edges as orthogonal polylines with arrowheads). ----------------

const _pad = 16.0;
const _nodeFill = '#ececff';
const _nodeStroke = '#9b8fd6';
const _clusterFill = '#f6f4fc';
const _clusterStroke = '#c8bfe8';
const _edgeStroke = '#6b5fb0';

String _renderSvg(
  ElkResult r,
  ElkGraph input,
  Map<String, String> labels,
  String title,
) {
  final w = r.width + _pad * 2;
  final h = r.height + _pad * 2;
  final marker =
      'arrow-${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
  final thickness = <String, double>{};
  void collectEdges(List<ElkNode> nodes, List<ElkEdge> edges) {
    for (final edge in edges) {
      thickness[edge.id] = edge.thickness;
    }
    for (final node in nodes) {
      collectEdges(node.children, node.edges);
    }
  }

  collectEdges(input.children, input.edges);
  final b = StringBuffer();
  b.writeln(
    '<svg viewBox="0 0 ${_n(w)} ${_n(h)}" '
    'width="${_n(w)}" height="${_n(h)}" '
    'style="min-width: ${_n(w > 900 ? 900 : w)}px; flex-shrink: 0" '
    'xmlns="http://www.w3.org/2000/svg" class="elk-svg" role="img">',
  );
  b.writeln('<title>${_esc(title)}</title>');
  b.writeln(
    '<defs><marker id="$marker" viewBox="0 0 10 10" refX="9" refY="5" '
    'markerWidth="6" markerHeight="6" orient="auto-start-reverse">'
    '<path d="M0,0 L10,5 L0,10 z" fill="$_edgeStroke"/></marker></defs>',
  );
  b.writeln('<g transform="translate(${_n(_pad)},${_n(_pad)})">');

  void drawLabel(
    ElkPositionedLabel label,
    double dx,
    double dy, {
    String cssClass = 'edge-label',
    bool backing = false,
  }) {
    final x = dx + label.x, y = dy + label.y;
    if (backing) {
      b.writeln(
        '<rect x="${_n(x)}" y="${_n(y)}" '
        'width="${_n(label.width)}" height="${_n(label.height)}" '
        'rx="2" fill="#fff" fill-opacity="0.94"/>',
      );
    }
    b.writeln(
      '<text x="${_n(x + label.width / 2)}" '
      'y="${_n(y + label.height / 2)}" class="$cssClass" '
      'text-anchor="middle" dominant-baseline="central">'
      '${_esc(label.text)}</text>',
    );
  }

  void drawNodes(List<ElkPositionedNode> nodes, double dx, double dy) {
    for (final n in nodes) {
      final ax = n.x + dx, ay = n.y + dy;
      final compound = n.children.isNotEmpty;
      b.writeln(
        '<rect x="${_n(ax)}" y="${_n(ay)}" width="${_n(n.width)}" '
        'height="${_n(n.height)}" rx="${compound ? 8 : 6}" '
        'fill="${compound ? _clusterFill : _nodeFill}" '
        'stroke="${compound ? _clusterStroke : _nodeStroke}" '
        '${compound ? 'stroke-dasharray="4 3"' : ''}/>',
      );
      if (n.labels.isNotEmpty) {
        for (final label in n.labels) {
          drawLabel(
            label,
            ax,
            ay,
            cssClass: compound ? 'cluster-label' : 'node-label',
          );
        }
      } else if (compound) {
        if (labels[n.id] case final String label) {
          b.writeln(
            '<text x="${_n(ax + 2)}" y="${_n(ay - 5)}" '
            'class="cluster-label">${_esc(label)}</text>',
          );
        }
      } else {
        b.writeln(
          '<text x="${_n(ax + n.width / 2)}" '
          'y="${_n(ay + n.height / 2)}" class="node-label" '
          'text-anchor="middle" dominant-baseline="central">'
          '${_esc(labels[n.id] ?? n.id)}</text>',
        );
      }
      drawNodes(n.children, ax, ay);
    }
  }

  drawNodes(r.children, 0, 0);

  for (final edge in r.edges) {
    for (final section in edge.sections) {
      final points = section.points
          .map((p) => '${_n(p.x)},${_n(p.y)}')
          .join(' ');
      b.writeln(
        '<polyline points="$points" fill="none" stroke="$_edgeStroke" '
        'stroke-width="${_n(thickness[edge.id] ?? 1)}" '
        'marker-end="url(#$marker)"/>',
      );
    }
    for (final point in edge.junctionPoints) {
      b.writeln(
        '<circle cx="${_n(point.x)}" cy="${_n(point.y)}" '
        'r="2.5" fill="$_edgeStroke"/>',
      );
    }
    for (final label in edge.labels) {
      drawLabel(label, 0, 0, backing: true);
    }
  }

  void drawPorts(List<ElkPositionedNode> nodes, double dx, double dy) {
    for (final node in nodes) {
      final ax = node.x + dx, ay = node.y + dy;
      for (final port in node.ports) {
        b.writeln(
          '<rect x="${_n(ax + port.x)}" y="${_n(ay + port.y)}" '
          'width="${_n(port.width)}" height="${_n(port.height)}" '
          'fill="#f7e6a0" stroke="#8e6d24"/>',
        );
        for (final label in port.labels) {
          drawLabel(label, ax + port.x, ay + port.y, cssClass: 'port-label');
        }
      }
      drawPorts(node.children, ax, ay);
    }
  }

  drawPorts(r.children, 0, 0);
  b.writeln('</g></svg>');
  return b.toString();
}

String _n(double v) => v.toStringAsFixed(1);
String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
