/// A Flutter widget embedded into the `/elk` page via `jaspr_flutter_embed`,
/// demonstrating that `elk` lays out **real Flutter widgets**: each
/// node below is a live Material card placed at the coordinates ELK computes,
/// with the orthogonal edges drawn by a [CustomPainter]. The whole canvas is
/// pan/zoomable and the cards are tappable.
///
/// This file imports Flutter, so it is only compiled for the web build; the
/// Jaspr component references it through an `@Import.onWeb` stub.
library;

import 'dart:math' as math;

import 'package:elk/elk.dart';
import 'package:flutter/material.dart';

/// One node's presentation: a label and an icon. Its box size is fixed so the
/// layout (which needs sizes up front) matches the rendered widget exactly.
class _NodeSpec {
  const _NodeSpec(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

const double _nodeW = 168;
const double _nodeH = 56;

// A small Flutter widget tree, laid out by ELK top-to-bottom.
const _nodes = <_NodeSpec>[
  _NodeSpec('app', 'MaterialApp', Icons.flutter_dash),
  _NodeSpec('scaffold', 'Scaffold', Icons.web_asset),
  _NodeSpec('appbar', 'AppBar', Icons.view_headline),
  _NodeSpec('body', 'Column', Icons.view_column),
  _NodeSpec('text', 'Text', Icons.title),
  _NodeSpec('button', 'ElevatedButton', Icons.smart_button),
  _NodeSpec('list', 'ListView', Icons.list),
];

const _edges = <(String, String)>[
  ('app', 'scaffold'),
  ('scaffold', 'appbar'),
  ('scaffold', 'body'),
  ('body', 'text'),
  ('body', 'button'),
  ('body', 'list'),
];

class ElkFlutterApp extends StatelessWidget {
  const ElkFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4a3a8a),
        fontFamily: 'Inter',
      ),
      home: const Scaffold(
        backgroundColor: Colors.white,
        body: _ElkCanvas(),
      ),
    );
  }
}

class _ElkCanvas extends StatefulWidget {
  const _ElkCanvas();

  @override
  State<_ElkCanvas> createState() => _ElkCanvasState();
}

class _ElkCanvasState extends State<_ElkCanvas> {
  late final ElkResult _result;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _result = const ElkLayered().layout(ElkGraph(
      layoutOptions: const ElkLayoutOptions(direction: ElkDirection.down),
      children: [
        for (final n in _nodes)
          ElkNode(id: n.id, width: _nodeW, height: _nodeH),
      ],
      edges: [
        for (var i = 0; i < _edges.length; i++)
          ElkEdge(id: 'e$i', sources: [_edges[i].$1], targets: [_edges[i].$2]),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _result.nodesById;
    final size = Size(_result.width, _result.height);
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(120),
      minScale: 0.4,
      maxScale: 3,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            children: [
              // Edges behind the nodes.
              Positioned.fill(
                child: CustomPaint(
                  painter: _EdgePainter(_result.edges),
                ),
              ),
              // Each node is a real, tappable Flutter card.
              for (final spec in _nodes)
                if (nodes[spec.id] case final n?)
                  Positioned(
                    left: n.x,
                    top: n.y,
                    width: n.width,
                    height: n.height,
                    child: _NodeCard(
                      spec: spec,
                      selected: _selected == spec.id,
                      onTap: () => setState(
                          () => _selected = _selected == spec.id ? null : spec.id),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.spec,
    required this.selected,
    required this.onTap,
  });
  final _NodeSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4a3a8a);
    return Material(
      color: selected ? accent : const Color(0xFFECECFF),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF9b8fd6)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(spec.icon,
                  size: 20, color: selected ? Colors.white : accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  spec.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : const Color(0xFF33335a),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints each edge's orthogonal sections plus an arrowhead at the target end.
class _EdgePainter extends CustomPainter {
  _EdgePainter(this.edges);
  final List<ElkPositionedEdge> edges;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF6b5fb0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = const Color(0xFF6b5fb0);

    for (final e in edges) {
      if (e.sections.isEmpty) continue;
      final pts = e.sections.first.points;
      if (pts.length < 2) continue;
      final path = Path()..moveTo(pts.first.x, pts.first.y);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].x, pts[i].y);
      }
      canvas.drawPath(path, stroke);
      _arrowHead(canvas, fill, pts[pts.length - 2], pts.last);
    }
  }

  void _arrowHead(Canvas canvas, Paint fill, ElkPoint from, ElkPoint tip) {
    final dx = tip.x - from.x, dy = tip.y - from.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final ux = dx / len, uy = dy / len; // unit direction
    const s = 8.0;
    final baseX = tip.x - ux * s, baseY = tip.y - uy * s;
    final perpX = -uy, perpY = ux;
    final p = Path()
      ..moveTo(tip.x, tip.y)
      ..lineTo(baseX + perpX * (s * 0.5), baseY + perpY * (s * 0.5))
      ..lineTo(baseX - perpX * (s * 0.5), baseY - perpY * (s * 0.5))
      ..close();
    canvas.drawPath(p, fill);
  }

  @override
  bool shouldRepaint(_EdgePainter oldDelegate) => false;
}
