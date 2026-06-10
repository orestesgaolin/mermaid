/// Sequence diagram layout: bespoke column-per-participant positioning,
/// ported (simplified) from upstream sequenceRenderer.ts / svgDraw.ts.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';
import 'sequence_model.dart';

/// Upstream sequence config defaults (config.schema.yaml).
const double _diagramMarginX = 50;
const double _diagramMarginY = 10;
const double _actorMargin = 50;
const double _actorMinWidth = 150;
const double _actorHeight = 65;
const double _boxMargin = 10;
const double _boxTextMargin = 5;
const double _noteMargin = 10;
const double _messageMargin = 35;
const double _activationWidth = 10;
const double _blockLabelHeight = 24;

// theme-default note/activation colors (not yet part of MermaidTheme).
const _noteBkg = Color(0xfffff5ad);
const _noteBorder = Color(0xffaaaa33);
const _activationBkg = Color(0xfff4f4f4);
const _activationBorder = Color(0xff666666);
const _lifelineColor = Color(0xffb3a2e3);
// Upstream .loopLine / labelBox styling.
const _frameBorder = Color(0xffccccff);

RenderScene layoutSequence(
  SequenceDiagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  return _SequenceLayout(diagram, measurer, theme).run();
}

class _Column {
  _Column(this.participant, this.boxWidth, this.labelSize);

  final SeqParticipant participant;
  final double boxWidth;
  final Size labelSize;
  double x = 0; // lifeline center
}

class _OpenFrame {
  _OpenFrame(this.start, this.startY);

  final SeqBlockStart start;
  final double startY;
  final dividers = <(double, String)>[];
  double minX = double.infinity;
  double maxX = double.negativeInfinity;
  int depth = 0;

  void include(double x1, double x2) {
    minX = math.min(minX, math.min(x1, x2));
    maxX = math.max(maxX, math.max(x1, x2));
  }
}

class _SequenceLayout {
  _SequenceLayout(this.diagram, this.measurer, this.theme)
      : baseStyle = TextStyleSpec(
          fontFamily: theme.fontFamily,
          fontSize: theme.fontSize,
        );

  final SequenceDiagram diagram;
  final TextMeasurer measurer;
  final MermaidTheme theme;
  final TextStyleSpec baseStyle;

  final columns = <String, _Column>{};
  final order = <String>[];

  // Output buckets in paint order.
  final backgrounds = <SceneNode>[]; // rect-block fills
  final frames = <SceneNode>[]; // loop/alt/... frames (above bg, below rest)
  final frameLabels = <SceneNode>[]; // tabs + divider labels (top-most)
  final lifelines = <SceneNode>[];
  final activationNodes = <SceneNode>[];
  final eventNodes = <SceneNode>[];
  final actorNodes = <SceneNode>[];

  double y = 0;

  RenderScene run() {
    _buildColumns();
    final topBoxBottom = _actorHeight;
    y = topBoxBottom;

    final openActivations = <String, List<double>>{};
    final activationRects = <(String, double, double, int)>[];
    final openFrames = <_OpenFrame>[];
    var autonumber = false;
    var autoValue = 0;
    var autoStep = 1;

    void includeInFrames(double x1, double x2) {
      for (final f in openFrames) {
        f.include(x1, x2);
      }
    }

    for (final event in diagram.events) {
      switch (event) {
        case SeqAutonumber():
          autonumber = event.on;
          if (event.on) {
            autoValue = (event.start ?? 1) - (event.step ?? 1);
            autoStep = event.step ?? 1;
            autoValue = event.start != null ? event.start! - autoStep : 0;
          }

        case SeqMessage():
          autoValue += autonumber ? autoStep : 0;
          final number = autonumber ? autoValue : null;
          if (event.from == event.to) {
            _selfMessage(event, number, includeInFrames);
          } else {
            _message(event, number, openActivations, includeInFrames);
          }

        case SeqActivation():
          final stack = openActivations.putIfAbsent(event.id, () => []);
          if (event.active) {
            stack.add(y);
          } else if (stack.isNotEmpty) {
            activationRects
                .add((event.id, stack.removeLast(), y, stack.length));
          }

        case SeqNote():
          _note(event, includeInFrames);

        case SeqBlockStart():
          y += _boxMargin;
          final frame = _OpenFrame(event, y)..depth = openFrames.length;
          openFrames.add(frame);
          if (event.kind != SeqBlockKind.rect) {
            y += _blockLabelHeight +
                (event.label.isEmpty
                    ? 0
                    : measurer.measure(event.label, baseStyle).height);
          }

        case SeqBlockDivider():
          y += _boxMargin;
          openFrames.last.dividers.add((y, event.label));
          y += _blockLabelHeight;

        case SeqBlockEnd():
          y += _boxMargin;
          final frame = openFrames.removeLast();
          _emitFrame(frame, y);
          y += _boxMargin;
      }
    }

    // Close any activations left open at the bottom.
    openActivations.forEach((id, stack) {
      for (var i = 0; i < stack.length; i++) {
        activationRects.add((id, stack[i], y + _boxMargin, i));
      }
    });

    final bottomBoxTop = y + 2 * _boxMargin;

    for (final (id, startY, endY, depth) in activationRects) {
      final cx = columns[id]!.x + depth * 3;
      activationNodes.add(SceneShape(
        geometry: RectGeometry(Rect.fromLTWH(
            cx - _activationWidth / 2, startY, _activationWidth, endY - startY)),
        fill: const Fill(_activationBkg),
        stroke: const Stroke(color: _activationBorder),
      ));
    }

    for (final id in order) {
      final col = columns[id]!;
      lifelines.add(SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(col.x, topBoxBottom)),
          LineTo(Point(col.x, bottomBoxTop)),
        ]),
        stroke: const Stroke(color: _lifelineColor, width: 1),
      ));
      _actorBox(col, 0);
      // mirrorActors: repeat the participant box at the bottom.
      _actorBox(col, bottomBoxTop);
    }

    var nodes = <SceneNode>[
      ...backgrounds,
      ...frames,
      ...lifelines,
      ...activationNodes,
      ...actorNodes,
      ...eventNodes,
      ...frameLabels,
    ];
    var bounds = sceneBounds(nodes) ??
        Rect.fromLTWH(0, 0, _actorMinWidth, _actorHeight);

    final title = diagram.title;
    if (title != null && title.isNotEmpty) {
      final style = baseStyle.copyWith(fontWeight: 700);
      final size = measurer.measure(title, style);
      final node = SceneText(
        text: title,
        bounds: Rect.fromLTWH(bounds.center.x - size.width / 2,
            bounds.top - size.height - 8, size.width, size.height),
        style: style,
        color: theme.titleColor,
      );
      nodes = [...nodes, node];
      bounds = bounds.union(node.bounds);
    }

    final dx = _diagramMarginX / 2 - bounds.left;
    final dy = _diagramMarginY - bounds.top;
    return RenderScene(
      size: Size(bounds.width + _diagramMarginX, bounds.height + 2 * _diagramMarginY),
      background: theme.background,
      nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
    );
  }

  // --- columns ---------------------------------------------------------------

  void _buildColumns() {
    for (final p in diagram.participants.values) {
      final labelSize = measurer.measure(p.label, baseStyle, maxWidth: 200);
      final w = math.max(_actorMinWidth, labelSize.width + 2 * _boxTextMargin * 2);
      order.add(p.id);
      columns[p.id] = _Column(p, w, labelSize);
    }
    if (order.isEmpty) {
      return;
    }

    // Minimum center distance between adjacent columns, widened by message
    // and note text between that pair (upstream calculateActorMargins).
    final minGap = List<double>.filled(math.max(0, order.length - 1), 0);
    double need(String a, String b, double width) {
      final ia = order.indexOf(a);
      final ib = order.indexOf(b);
      if (ia < 0 || ib < 0 || ia == ib) return 0;
      final lo = math.min(ia, ib);
      final hi = math.max(ia, ib);
      // Spread the requirement across the spanned gaps.
      return width / (hi - lo);
    }

    void widen(String a, String b, double width) {
      final ia = order.indexOf(a);
      final ib = order.indexOf(b);
      if (ia < 0 || ib < 0 || ia == ib) return;
      final lo = math.min(ia, ib);
      final hi = math.max(ia, ib);
      final per = need(a, b, width);
      for (var i = lo; i < hi; i++) {
        minGap[i] = math.max(minGap[i], per);
      }
    }

    for (final event in diagram.events) {
      switch (event) {
        case SeqMessage(:final from, :final to, :final text):
          if (text.isEmpty) break;
          final w = measurer.measure(text, baseStyle).width + 2 * _boxTextMargin;
          if (from == to) {
            // Self message text hangs to the right of the lifeline.
            final i = order.indexOf(from);
            if (i >= 0 && i < minGap.length) {
              minGap[i] = math.max(minGap[i], w + 40);
            }
          } else {
            widen(from, to, w);
          }
        case SeqNote(:final placement, :final target, :final target2, :final text):
          final w = measurer.measure(text, baseStyle, maxWidth: 250).width +
              2 * _noteMargin;
          if (placement == NotePlacement.over && target2 != null) {
            widen(target, target2, w - 50);
          } else if (placement != NotePlacement.over) {
            final i = order.indexOf(target);
            final gapIndex = placement == NotePlacement.rightOf ? i : i - 1;
            if (gapIndex >= 0 && gapIndex < minGap.length) {
              minGap[gapIndex] = math.max(minGap[gapIndex], w + 10);
            }
          }
        default:
          break;
      }
    }

    var x = columns[order.first]!.boxWidth / 2;
    columns[order.first]!.x = x;
    for (var i = 1; i < order.length; i++) {
      final prev = columns[order[i - 1]]!;
      final cur = columns[order[i]]!;
      final centerDist = prev.boxWidth / 2 +
          cur.boxWidth / 2 +
          math.max(_actorMargin, minGap[i - 1]);
      x += centerDist;
      cur.x = x;
    }
  }

  // --- drawing ----------------------------------------------------------------

  void _actorBox(_Column col, double top) {
    final p = col.participant;
    final rect = Rect.fromLTWH(
        col.x - col.boxWidth / 2, top, col.boxWidth, _actorHeight);
    final children = <SceneNode>[];
    if (p.isActor) {
      // Stick figure above the name.
      final cx = col.x;
      final headY = top + 12;
      children.addAll([
        SceneShape(
          geometry: CircleGeometry(Point(cx, headY), 7),
          stroke: Stroke(color: theme.nodeBorder, width: 1.5),
          fill: Fill(theme.mainBkg),
        ),
        SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(cx, headY + 7)),
            LineTo(Point(cx, headY + 25)),
            MoveTo(Point(cx - 10, headY + 13)),
            LineTo(Point(cx + 10, headY + 13)),
            MoveTo(Point(cx, headY + 25)),
            LineTo(Point(cx - 8, headY + 37)),
            MoveTo(Point(cx, headY + 25)),
            LineTo(Point(cx + 8, headY + 37)),
          ]),
          stroke: Stroke(color: theme.nodeBorder, width: 1.5),
        ),
        SceneText(
          text: p.label,
          bounds: Rect.fromLTWH(col.x - col.labelSize.width / 2,
              headY + 39, col.labelSize.width, col.labelSize.height),
          style: baseStyle,
          color: theme.textColor,
        ),
      ]);
    } else {
      children.addAll([
        SceneShape(
          geometry: RectGeometry(rect, rx: 3, ry: 3),
          fill: Fill(theme.mainBkg),
          stroke: Stroke(color: theme.nodeBorder),
        ),
        SceneText(
          text: p.label,
          bounds: Rect.fromCenter(
              rect.center, col.labelSize.width, col.labelSize.height),
          style: baseStyle,
          color: theme.textColor,
        ),
      ]);
    }
    actorNodes.add(SceneGroup(
      id: 'actor_${p.id}${top > 0 ? '_bottom' : ''}',
      semanticLabel: p.label,
      children: children,
    ));
  }

  void _message(SeqMessage msg, int? number,
      Map<String, List<double>> activations,
      void Function(double, double) include) {
    final fromCol = columns[msg.from]!;
    final toCol = columns[msg.to]!;
    final textSize =
        msg.text.isEmpty ? Size.zero : measurer.measure(msg.text, baseStyle);
    y += math.max(_messageMargin, textSize.height + 14);

    final dir = toCol.x > fromCol.x ? 1.0 : -1.0;
    // Leave the activation bar edge rather than the lifeline center.
    double edge(String id, _Column col) {
      final depth = activations[id]?.length ?? 0;
      if (depth == 0) return col.x;
      return col.x + (depth - 1) * 3 + dir * _activationWidth / 2 * 0;
    }

    final x1 = edge(msg.from, fromCol);
    final x2 = toCol.x;
    final children = <SceneNode>[];

    if (msg.text.isNotEmpty) {
      children.add(SceneText(
        text: msg.text,
        bounds: Rect.fromLTWH((x1 + x2) / 2 - textSize.width / 2,
            y - textSize.height - 4, textSize.width, textSize.height),
        style: baseStyle,
        color: theme.textColor,
      ));
    }

    children.add(SceneShape(
      geometry: PathGeometry([MoveTo(Point(x1, y)), LineTo(Point(x2, y))]),
      stroke: Stroke(
        color: theme.lineColor,
        width: 1.5,
        dash: msg.arrow.dotted ? const [3, 3] : null,
      ),
    ));

    children.addAll(_head(msg.arrow, Point(x2, y), Point(dir, 0)));
    if (msg.arrow.bidirectional) {
      children.addAll(
          _head(SeqArrow.solidArrow, Point(x1, y), Point(-dir, 0)));
    }
    if (number != null) {
      children.addAll(_numberBadge(number, Point(x1, y)));
    }

    eventNodes.add(SceneGroup(
      id: 'msg_${msg.from}_${msg.to}',
      semanticLabel: msg.text.isEmpty ? null : msg.text,
      children: children,
    ));
    include(math.min(x1, x2), math.max(x1, x2));
    y += 4;
  }

  void _selfMessage(SeqMessage msg, int? number,
      void Function(double, double) include) {
    final col = columns[msg.from]!;
    final textSize =
        msg.text.isEmpty ? Size.zero : measurer.measure(msg.text, baseStyle);
    y += _messageMargin;
    final x = col.x;
    const out = 34.0;
    final h = math.max(20.0, textSize.height + 6);
    final children = <SceneNode>[
      SceneShape(
        geometry: PathGeometry([
          MoveTo(Point(x, y)),
          CubicTo(Point(x + out, y - 6), Point(x + out, y + h + 6),
              Point(x + 4, y + h)),
        ]),
        stroke: Stroke(
          color: theme.lineColor,
          width: 1.5,
          dash: msg.arrow.dotted ? const [3, 3] : null,
        ),
      ),
      ..._head(msg.arrow, Point(x + 2, y + h), const Point(-1, 0.2)),
      if (msg.text.isNotEmpty)
        SceneText(
          text: msg.text,
          bounds: Rect.fromLTWH(x + out * 0.85, y + h / 2 - textSize.height / 2,
              textSize.width, textSize.height),
          style: baseStyle,
          color: theme.textColor,
          align: TextAlignH.left,
        ),
      if (number != null) ..._numberBadge(number, Point(x, y)),
    ];
    eventNodes.add(SceneGroup(
      id: 'msg_${msg.from}_${msg.from}',
      semanticLabel: msg.text.isEmpty ? null : msg.text,
      children: children,
    ));
    include(x, x + out + textSize.width);
    y += h + 4;
  }

  List<SceneNode> _head(SeqArrow arrow, Point tip, Point dir) {
    final d = _norm(dir);
    final perp = Point(-d.y, d.x);
    switch (arrow) {
      case SeqArrow.solidArrow ||
            SeqArrow.dottedArrow ||
            SeqArrow.bidirectionalSolid ||
            SeqArrow.bidirectionalDotted:
        final base = tip - d * 10;
        return [
          SceneShape(
            geometry:
                PolygonGeometry([tip, base + perp * 5, base - perp * 5]),
            fill: Fill(theme.arrowheadColor),
          ),
        ];
      case SeqArrow.solidPoint || SeqArrow.dottedPoint:
        final base = tip - d * 10;
        return [
          SceneShape(
            geometry: PathGeometry([
              MoveTo(base + perp * 5),
              LineTo(tip),
              LineTo(base - perp * 5),
            ]),
            stroke: Stroke(color: theme.arrowheadColor, width: 1.5),
          ),
        ];
      case SeqArrow.solidCross || SeqArrow.dottedCross:
        final c = tip - d * 6;
        const arm = 4.5;
        final d1 = (d + perp) * (arm / math.sqrt2);
        final d2 = (d - perp) * (arm / math.sqrt2);
        return [
          SceneShape(
            geometry: PathGeometry([
              MoveTo(c - d1),
              LineTo(c + d1),
              MoveTo(c - d2),
              LineTo(c + d2),
            ]),
            stroke: Stroke(color: theme.arrowheadColor, width: 1.8),
          ),
        ];
      case SeqArrow.solidOpen || SeqArrow.dottedOpen:
        return const [];
    }
  }

  List<SceneNode> _numberBadge(int number, Point center) {
    final text = '$number';
    final style = baseStyle.copyWith(fontSize: baseStyle.fontSize * 0.75);
    final size = measurer.measure(text, style);
    // Upstream sequenceNumber: solid dark circle with inverted text, sitting
    // on the lifeline at the message start.
    return [
      SceneShape(
        geometry: CircleGeometry(center, math.max(8, size.width / 2 + 3)),
        fill: Fill(theme.lineColor),
      ),
      SceneText(
        text: text,
        bounds: Rect.fromCenter(center, size.width, size.height),
        style: style,
        color: theme.background,
      ),
    ];
  }

  void _note(SeqNote note, void Function(double, double) include) {
    final textSize = measurer.measure(note.text, baseStyle, maxWidth: 250);
    final w = textSize.width + 2 * _noteMargin;
    final h = textSize.height + 2 * _noteMargin;
    final col = columns[note.target]!;
    double left;
    double width = w;
    switch (note.placement) {
      case NotePlacement.rightOf:
        left = col.x + _activationWidth;
      case NotePlacement.leftOf:
        left = col.x - _activationWidth - w;
      case NotePlacement.over:
        if (note.target2 != null) {
          final col2 = columns[note.target2!]!;
          final lo = math.min(col.x, col2.x) - 25;
          final hi = math.max(col.x, col2.x) + 25;
          left = lo;
          width = math.max(hi - lo, w);
          // Center the requested width over the span.
          if (w > width) width = w;
          left = (lo + hi) / 2 - width / 2;
        } else {
          left = col.x - w / 2;
        }
    }
    y += _boxMargin;
    eventNodes.add(SceneGroup(
      id: 'note',
      semanticLabel: note.text,
      children: [
        SceneShape(
          geometry: RectGeometry(Rect.fromLTWH(left, y, width, h)),
          fill: const Fill(_noteBkg),
          stroke: const Stroke(color: _noteBorder),
        ),
        SceneText(
          text: note.text,
          bounds: Rect.fromLTWH(left + (width - textSize.width) / 2,
              y + _noteMargin, textSize.width, textSize.height),
          style: baseStyle,
          color: Color.black,
        ),
      ],
    ));
    include(left, left + width);
    y += h + _boxMargin;
  }

  void _emitFrame(_OpenFrame frame, double endY) {
    if (!frame.minX.isFinite) {
      // Empty block: give it a nominal extent around the first column.
      final first = columns[order.first]!;
      frame.include(first.x - 20, first.x + 20);
    }
    final inset = 10.0 + frame.depth * 6;
    final rect = Rect.fromLTRB(
        frame.minX - inset, frame.startY, frame.maxX + inset, endY);

    if (frame.start.kind == SeqBlockKind.rect) {
      final fill = Color.tryParse(frame.start.color ?? '') ??
          const Color(0x11888888);
      backgrounds.add(SceneShape(
        geometry: RectGeometry(rect),
        fill: Fill(fill),
      ));
      return;
    }

    final keyword = switch (frame.start.kind) {
      SeqBlockKind.loop => 'loop',
      SeqBlockKind.alt => 'alt',
      SeqBlockKind.opt => 'opt',
      SeqBlockKind.par => 'par',
      SeqBlockKind.critical => 'critical',
      SeqBlockKind.breakBlock => 'break',
      SeqBlockKind.rect => '',
    };
    final keywordStyle = baseStyle.copyWith(fontWeight: 700);
    final kwSize = measurer.measure(keyword, keywordStyle);
    final tabW = kwSize.width + 2 * _boxTextMargin + 8;
    final tabH = kwSize.height + 4;

    frames.add(SceneGroup(id: 'frame_$keyword', children: [
      SceneShape(
        geometry: RectGeometry(rect),
        stroke: const Stroke(color: _frameBorder, dash: [2, 2]),
      ),
      for (final (dy, _) in frame.dividers)
        SceneShape(
          geometry: PathGeometry(
              [MoveTo(Point(rect.left, dy)), LineTo(Point(rect.right, dy))]),
          stroke: const Stroke(color: _frameBorder, dash: [2, 2]),
        ),
    ]));
    // Tab and labels paint above everything (activation bars would occlude
    // centered divider labels otherwise).
    final labelChildren = <SceneNode>[
      // Pentagon label tab, upstream labelBox shape.
      SceneShape(
        geometry: PolygonGeometry([
          Point(rect.left, rect.top),
          Point(rect.left + tabW, rect.top),
          Point(rect.left + tabW, rect.top + tabH - 6),
          Point(rect.left + tabW - 6, rect.top + tabH),
          Point(rect.left, rect.top + tabH),
        ]),
        fill: Fill(theme.mainBkg),
        stroke: const Stroke(color: _frameBorder),
      ),
      SceneText(
        text: keyword,
        bounds: Rect.fromLTWH(rect.left + _boxTextMargin, rect.top + 2,
            kwSize.width, kwSize.height),
        style: keywordStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ),
      if (frame.start.label.isNotEmpty)
        _frameLabel(frame.start.label,
            Point(rect.left + tabW + 8, rect.top + 2)),
    ];
    for (final (dy, label) in frame.dividers) {
      if (label.isEmpty) continue;
      final size = measurer.measure('[$label]', baseStyle);
      labelChildren.add(SceneShape(
        geometry: RectGeometry(
            Rect.fromLTWH(rect.center.x - size.width / 2 - 3, dy + 2,
                size.width + 6, size.height + 2),
            rx: 2,
            ry: 2),
        fill: Fill(theme.edgeLabelBackground),
      ));
      labelChildren
          .add(_frameLabel('[$label]', Point(rect.center.x, dy + 3),
              centered: true));
    }
    frameLabels
        .add(SceneGroup(id: 'framelabel_$keyword', children: labelChildren));
  }

  SceneText _frameLabel(String text, Point topLeft, {bool centered = false}) {
    final size = measurer.measure('[$text]', baseStyle);
    final t = text.startsWith('[') ? text : '[$text]';
    return SceneText(
      text: t,
      bounds: Rect.fromLTWH(centered ? topLeft.x - size.width / 2 : topLeft.x,
          topLeft.y, size.width, size.height),
      style: baseStyle,
      color: theme.textColor,
      align: centered ? TextAlignH.center : TextAlignH.left,
    );
  }

  Point _norm(Point p) {
    final len = math.sqrt(p.x * p.x + p.y * p.y);
    return len == 0 ? const Point(1, 0) : Point(p.x / len, p.y / len);
  }
}
