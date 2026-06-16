// Experiment: reproduce the hierarchical dataflow layout from the
// eclipse-elk README (the "complexRouter" example) with elk_layout, now using
// PORTS so edges attach at distinct points on node borders. Run from the
// package root:
//
//   dart run example/readme_repro.dart > /tmp/elk_repro.svg
import 'package:elk_layout/elk_layout.dart';

final _labels = <String, String>{};
final _outPorts = <String, List<ElkPort>>{}; // nodeId -> output ports
final _inPorts = <String, List<ElkPort>>{}; // nodeId -> input ports
final _edges = <ElkEdge>[];
var _pc = 0;

// Wire an edge from [from] to [to], minting a dedicated output port on the
// source and input port on the target (the way the original models it).
void link(String from, String to) {
  final sp = ElkPort(id: '${from}__o${_pc}');
  final tp = ElkPort(id: '${to}__i${_pc}');
  _pc++;
  (_outPorts[from] ??= []).add(sp);
  (_inPorts[to] ??= []).add(tp);
  _edges.add(ElkEdge(id: 'e${_edges.length}', sources: [sp.id], targets: [tp.id]));
}

final _sharedPorts = <String, ElkPort>{};

// Wire an edge whose source is a FIXED east-side output port shared across
// several edges (exactly how the original models q1/q2: one east port P11
// carries both the MonitorValue output and the feedback to QueueControl). A
// feedback edge leaving the east side must therefore route all the way around
// the diagram back to QueueControl's west side.
void linkVia(String from, String sharedOutId, String to,
    {bool fixedWestTarget = false}) {
  final sp = _sharedPorts.putIfAbsent(sharedOutId, () {
    final p = ElkPort(id: sharedOutId, side: ElkPortSide.east);
    (_outPorts[from] ??= []).add(p);
    return p;
  });
  // The feedback's target (QueueControl) has its input port fixed on the WEST
  // side (matching the original's P39/P41). Without this, the cycle-breaker
  // would flip the reversed edge's port to the east and the feedback would
  // enter QueueControl from the wrong (right) side instead of looping around to
  // the left.
  final tp = fixedWestTarget
      ? (ElkPort(id: '${to}__iw${_pc}', side: ElkPortSide.west))
      : ElkPort(id: '${to}__i${_pc}');
  _pc++;
  (_inPorts[to] ??= []).add(tp);
  _edges.add(ElkEdge(id: 'e${_edges.length}', sources: [sp.id], targets: [tp.id]));
}

ElkNode _leaf(String id, String label) {
  _labels[id] = label;
  final w = (label.length * 7.0 + 28).clamp(70.0, 240.0);
  return ElkNode(id: id, width: w, height: 40,
      ports: [...?_inPorts[id], ...?_outPorts[id]]);
}

ElkNode _cluster(String id, String label, List<ElkNode> children) {
  _labels[id] = label;
  return ElkNode(id: id, children: children,
      ports: [...?_inPorts[id], ...?_outPorts[id]]);
}

void main() {
  // Declare edges first so each node knows its ports before construction.
  link('reader', 'ramp');
  link('ramp', 'queue');
  link('queue', 'displayTop');
  link('queue', 'sleepF');
  link('queue', 'q1');
  link('queue', 'q2');
  link('queue', 'sleepS');
  link('sleepF', 'cntF');
  link('cntF', 'raF');
  link('raF', 'dispF');
  link('sleepS', 'cntS');
  link('cntS', 'raS');
  link('raS', 'dispS');
  // Each interface also drives its queue-length counter (q1/q2) and supplies the
  // second input of its channel's RecordAssembler (as in the real complexRouter).
  link('sleepF', 'q1');
  link('sleepS', 'q2');
  link('sleepF', 'raF');
  link('sleepS', 'raS');
  // q1/q2 each have ONE east output port (matching the original's P11/P22) that
  // feeds both the MonitorValue and the QueueControl feedback. The feedback thus
  // leaves the east side and loops around the diagram back to QueueControl.
  linkVia('q1', 'q1_out', 'monQ1');
  linkVia('q2', 'q2_out', 'monQ2');
  linkVia('q1', 'q1_out', 'queue', fixedWestTarget: true);
  linkVia('q2', 'q2_out', 'queue', fixedWestTarget: true);

  final graph = ElkGraph(
    layoutOptions: const ElkLayoutOptions(direction: ElkDirection.right),
    children: [
      _leaf('reader', 'DatagramReader'),
      _leaf('ramp', 'Ramp'),
      _cluster('router', 'router', [
        _leaf('queue', 'QueueControl'),
        _leaf('displayTop', 'Display'),
        _cluster('ifFast', 'Interface - fast', [_leaf('sleepF', 'Sleep')]),
        _cluster('ch1', 'channel1', [
          _leaf('cntF', 'Counter'),
          _leaf('raF', 'RecordAssembler'),
          _leaf('dispF', 'Display'),
        ]),
        _leaf('q1', 'Counter - q1'),
        _leaf('q2', 'Counter - q2'),
        _cluster('ifSlow', 'Interface - slow', [_leaf('sleepS', 'Sleep')]),
        _cluster('ch2', 'channel2', [
          _leaf('cntS', 'Counter'),
          _leaf('raS', 'RecordAssembler'),
          _leaf('dispS', 'Display'),
        ]),
      ]),
      _leaf('monQ1', 'MonitorValue - q1 length'),
      _leaf('monQ2', 'MonitorValue - q2 length'),
    ],
    edges: _edges,
  );

  final result = const ElkLayered().layout(graph);
  print(_renderSvg(result));
}

// --- minimal SVG renderer (clusters + leaves + ports + orthogonal edges) ----

String _renderSvg(ElkResult r) {
  const pad = 16.0;
  final b = StringBuffer();
  b.writeln('<svg viewBox="0 0 ${r.width + pad * 2} ${r.height + pad * 2}" '
      'xmlns="http://www.w3.org/2000/svg" style="background:white" '
      'font-family="Inter,sans-serif">');
  b.writeln('<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" '
      'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
      '<path d="M0,0 L10,5 L0,10 z" fill="#444"/></marker></defs>');
  b.writeln('<g transform="translate($pad,$pad)">');

  void clusters(List<ElkPositionedNode> ns, double dx, double dy) {
    for (final n in ns) {
      final ax = n.x + dx, ay = n.y + dy;
      if (n.children.isNotEmpty) {
        b.writeln('<rect x="$ax" y="$ay" width="${n.width}" height="${n.height}"'
            ' rx="4" fill="#dfe3f7" stroke="#9aa3d8"/>');
        // Draw the cluster label just above its box so it never overlaps the
        // child nodes inside.
        b.writeln('<text x="${ax + 2}" y="${ay - 4}" font-size="12" '
            'fill="#3a3a6a">${_labels[n.id] ?? ''}</text>');
        clusters(n.children, ax, ay);
      }
    }
  }

  void leaves(List<ElkPositionedNode> ns, double dx, double dy) {
    for (final n in ns) {
      final ax = n.x + dx, ay = n.y + dy;
      if (n.children.isNotEmpty) {
        leaves(n.children, ax, ay);
      } else {
        b.writeln('<rect x="$ax" y="$ay" width="${n.width}" height="${n.height}"'
            ' rx="3" fill="#c9cef0" stroke="#5b63b0"/>');
        b.writeln('<text x="${ax + n.width / 2}" y="${ay + n.height / 2 + 4}" '
            'font-size="12" text-anchor="middle" fill="#22224a">'
            '${_labels[n.id] ?? n.id}</text>');
      }
      // Port squares on every node (leaf or cluster).
      for (final p in n.ports) {
        b.writeln('<rect x="${ax + p.x - 3}" y="${ay + p.y - 3}" width="6" '
            'height="6" fill="#5b63b0"/>');
      }
    }
  }

  clusters(r.children, 0, 0);
  leaves(r.children, 0, 0);
  for (final e in r.edges) {
    if (e.sections.isEmpty) continue;
    final pts = e.sections.first.points.map((p) => '${p.x},${p.y}').join(' ');
    b.writeln('<polyline points="$pts" fill="none" stroke="#444" '
        'stroke-width="1.4" marker-end="url(#arrow)"/>');
  }
  b.writeln('</g></svg>');
  return b.toString();
}
