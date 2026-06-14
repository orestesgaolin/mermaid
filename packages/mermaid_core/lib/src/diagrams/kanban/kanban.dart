/// Kanban board (`kanban`): columns of stacked task cards. Indentation nests
/// tasks under the preceding column. Reference: upstream kanban db/renderer.
library;

import 'dart:math' as math;

import '../../color.dart';
import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

/// A single task card. Optional metadata (`ticket`/`priority`/`assigned`/
/// `icon`) is parsed from a trailing `@{ ... }` YAML-ish block, matching
/// upstream `kanbanDb.ts:addNode`.
class KanbanTask {
  KanbanTask(this.title);
  String title;
  String? ticket;
  String? priority;
  String? assigned;
  String? icon;
}

class KanbanColumn {
  KanbanColumn(this.title);
  final String title;

  /// Rich task cards with optional metadata.
  final cards = <KanbanTask>[];

  /// Task titles, in order. Backward-compatible view over [cards].
  List<String> get tasks => [for (final c in cards) c.title];
}

class KanbanBoard {
  const KanbanBoard(this.columns);
  final List<KanbanColumn> columns;
}

/// The node id and visible label parsed from a node line.
class _NodeHead {
  _NodeHead(this.id, this.label);
  final String? id;
  final String label;
}

/// Strips an optional `id[...]` / `id(...)` prefix and surrounding quotes,
/// returning the node id (if any) and the visible label. Matches upstream
/// node-id syntax loosely.
_NodeHead _parseHead(String s) {
  final t = s.trim();
  // `id[label]`, `id(label)`, `id((label))`, `id{{label}}` — id + inner label.
  final m =
      RegExp(r'^([^\s\[\(\{@]+)\s*[\[\(\{]+(.*?)[\]\)\}]+\s*$').firstMatch(t);
  String? id;
  String label;
  if (m != null) {
    id = m.group(1);
    label = m.group(2)!;
  } else {
    // Bare `id` with no brackets: id and label coincide (only when it is a
    // single token with no spaces; otherwise it is a plain label).
    final bare = RegExp(r'^(\S+)$').firstMatch(t);
    id = bare?.group(1);
    label = t;
  }
  if (label.length >= 2 && label.startsWith('"') && label.endsWith('"')) {
    label = label.substring(1, label.length - 1);
  }
  label = label.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  return _NodeHead(id, label);
}

/// Parses one `key: value` line from a `@{ ... }` block. Values may be quoted.
void _applyMeta(KanbanTask task, String key, String value) {
  var v = value.trim();
  if (v.length >= 2 &&
      ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'")))) {
    v = v.substring(1, v.length - 1);
  }
  switch (key.trim()) {
    case 'label':
    case 'descr':
      task.title = v.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
      break;
    case 'ticket':
      task.ticket = v;
      break;
    case 'priority':
      task.priority = _normalizePriority(v);
      break;
    case 'assigned':
      task.assigned = v;
      break;
    case 'icon':
      task.icon = v;
      break;
  }
}

/// Upstream `colorFromPriority` matches the exact strings
/// `Very High | High | Medium | Low | Very Low`. Be lenient about casing so
/// inputs like `high` still resolve.
String? _normalizePriority(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'very high':
      return 'Very High';
    case 'high':
      return 'High';
    case 'medium':
      return 'Medium';
    case 'low':
      return 'Low';
    case 'very low':
      return 'Very Low';
    default:
      return raw.trim();
  }
}

/// Priority → left-edge bar color (upstream `kanbanItem.ts:colorFromPriority`).
Color? _colorFromPriority(String? priority) {
  switch (priority) {
    case 'Very High':
      return const Color(0xffff0000); // red
    case 'High':
      return const Color(0xffffa500); // orange
    case 'Low':
      return const Color(0xff0000ff); // blue
    case 'Very Low':
      return const Color(0xffadd8e6); // lightblue
    case 'Medium':
    default:
      return null; // no stroke
  }
}

KanbanBoard parseKanban(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final columns = <KanbanColumn>[];
  var seenHeader = false;
  int? columnIndent;
  // The most recently added task, so a following `@{ ... }` block attaches.
  KanbanTask? lastTask;
  // Task ids → task, so an `id@{ ... }` block attaches to the named task even
  // when other lines intervene (upstream attaches by id).
  final tasksById = <String, KanbanTask>{};

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    var line = raw;
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c);
    if (line.trim().isEmpty) continue;
    if (!seenHeader) {
      if (!RegExp(r'^\s*kanban\b').hasMatch(line)) {
        throw MermaidParseException('expected "kanban" header', line: i + 1);
      }
      seenHeader = true;
      continue;
    }

    final trimmed = line.trim();

    // `style ...` / `class ...` directives are not yet honored; skip them so
    // they are never treated as nodes.
    if (RegExp(r'^(style|class|click|linkStyle)\b').hasMatch(trimmed)) {
      lastTask = null;
      continue;
    }

    // A `@{ ... }` shape-data block. May be on one line (`id@{ ... }`) or span
    // multiple lines. The id before `@{` names the target task; otherwise it
    // attaches to the most recently added task.
    final blockStart = RegExp(r'@\s*\{').firstMatch(trimmed);
    if (blockStart != null) {
      final prefix = trimmed.substring(0, blockStart.start).trim();
      final target = (prefix.isNotEmpty ? tasksById[prefix] : null) ?? lastTask;
      if (target == null) continue;
      final buffer = StringBuffer(trimmed.substring(blockStart.end));
      var closed = buffer.toString().contains('}');
      while (!closed && i + 1 < lines.length) {
        i++;
        final next = lines[i];
        if (next.contains('}')) {
          buffer.write('\n');
          buffer.write(next.substring(0, next.indexOf('}')));
          closed = true;
        } else {
          buffer.write('\n');
          buffer.write(next);
        }
      }
      // Strip a trailing `}` left on the opening line.
      var body = buffer.toString();
      final brace = body.indexOf('}');
      if (brace >= 0) body = body.substring(0, brace);
      _applyBlock(target, body);
      continue;
    }

    // Lines that begin with `@{` but have no preceding task are ignored.
    if (trimmed.startsWith('@')) continue;

    final indent = line.length - line.trimLeft().length;
    columnIndent ??= indent;
    final head = _parseHead(line);
    if (indent <= columnIndent) {
      columns.add(KanbanColumn(head.label));
      lastTask = null;
    } else if (columns.isNotEmpty) {
      final task = KanbanTask(head.label);
      columns.last.cards.add(task);
      if (head.id != null) tasksById[head.id!] = task;
      lastTask = task;
    }
  }
  if (!seenHeader) throw const MermaidParseException('empty kanban source');
  return KanbanBoard(columns);
}

/// Applies the `key: value` pairs found inside a `@{ ... }` block body.
void _applyBlock(KanbanTask task, String body) {
  for (final line in body.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final idx = t.indexOf(':');
    if (idx <= 0) continue;
    final key = t.substring(0, idx);
    final value = t.substring(idx + 1);
    _applyMeta(task, key, value);
  }
}

// Upstream renderer constants. `sectionWidth` defaults to 200; the renderer
// hardcodes `padding = 10`.
const _width = 200.0;
const _padding = 10.0;
// Item width = WIDTH - 1.5*padding (upstream kanbanRenderer.ts).
const _cardW = _width - 1.5 * _padding; // 185
// Inner label padding (upstream `labelPaddingX/Y = 10`).
const _labelPadX = 10.0;
const _labelPadY = 10.0;
// Default minimum label height upstream seeds `maxLabelHeight` with.
const _minLabelHeight = 25.0;

/// Section fill color for section index `s`. Upstream `styles.ts:genSections`
/// paints `.section-${i-1} rect` with `adjuster(cScale[i], 10)` where in light
/// mode `adjuster = lighten(_, 10)`. The `.section-${i-1}` offset means section
/// `s` uses loop `i = s + 1`, i.e. `cScale[(s + 1) % 12 ... ]` — section 0 maps
/// to `cScale2` (tertiaryColor). Sourced from the theme so non-default palettes
/// (dark/forest/neutral) adapt; the default theme is pixel-identical to the
/// previously-inlined constants (verified against khroma `lighten`).
Color _sectionFill(MermaidTheme theme, int s) {
  // section s -> loop i = s + 1; styles.ts paints class `.section-(i-1)` with
  // cScale[i]. Section 0 -> cScale[2]; wrap within the 12-entry palette.
  final cScale = theme.cScale;
  final color = cScale[(s + 2) % cScale.length];
  return _lighten(color, 10);
}

/// khroma `lighten(color, amount)`: HSL lightness += amount/100, clamped to
/// [0, 1]. Preserves alpha.
Color _lighten(Color c, double amount) {
  final hsl = _rgbToHsl(c.red, c.green, c.blue);
  final l = (hsl[2] + amount / 100).clamp(0.0, 1.0);
  final rgb = _hslToRgb(hsl[0], hsl[1], l);
  return Color.fromARGB(c.alpha, rgb[0], rgb[1], rgb[2]);
}

List<double> _rgbToHsl(int r, int g, int b) {
  final rr = r / 255, gg = g / 255, bb = b / 255;
  final mx = math.max(rr, math.max(gg, bb));
  final mn = math.min(rr, math.min(gg, bb));
  var h = 0.0, s = 0.0;
  final l = (mx + mn) / 2;
  if (mx != mn) {
    final d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == rr) {
      h = (gg - bb) / d + (gg < bb ? 6 : 0);
    } else if (mx == gg) {
      h = (bb - rr) / d + 2;
    } else {
      h = (rr - gg) / d + 4;
    }
    h /= 6;
  }
  return [h, s, l];
}

List<int> _hslToRgb(double h, double s, double l) {
  double r, g, b;
  if (s == 0) {
    r = g = b = l;
  } else {
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    r = _hue2rgb(p, q, h + 1 / 3);
    g = _hue2rgb(p, q, h);
    b = _hue2rgb(p, q, h - 1 / 3);
  }
  return [(r * 255).round(), (g * 255).round(), (b * 255).round()];
}

double _hue2rgb(double p, double q, double t) {
  if (t < 0) t += 1;
  if (t > 1) t -= 1;
  if (t < 1 / 6) return p + (q - p) * 6 * t;
  if (t < 1 / 2) return q;
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
  return p;
}

/// Section title text color. Upstream `.section-${i-1} text { fill:
/// cScaleLabel${i} }`; for default-theme sections this resolves to
/// `labelTextColor` = `#333333`. (The shared `theme.cScaleLabel` defaults to
/// pure black for these indices rather than `#333`, so sourcing it would change
/// the default render; kept inlined to preserve pixel-identity.)
const _sectionTextColor = Color(0xff333333);

RenderScene layoutKanban(
  KanbanBoard board, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  final baseStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final titleStyle = baseStyle.copyWith(fontWeight: 700);
  final nodes = <SceneNode>[];

  // First pass: measure each section label so all sections share one
  // `maxLabelHeight` (upstream seeds it at 25 and grows it).
  var maxLabelHeight = _minLabelHeight;
  final titleSizes = <Size>[];
  for (final col in board.columns) {
    final ts = measurer.measure(col.title, titleStyle, maxWidth: _width);
    titleSizes.add(ts);
    maxLabelHeight = math.max(maxLabelHeight, ts.height);
  }

  // The section label sits above the box; reserve that band so it never
  // overlaps neighbouring boards. `labelTop` is the y of the box top.
  final labelTop = maxLabelHeight;

  for (var ci = 0; ci < board.columns.length; ci++) {
    final col = board.columns[ci];
    final fill = _sectionFill(theme, ci);

    // Horizontal placement mirrors upstream `section.x = WIDTH*cnt +
    // (cnt-1)*padding/2` (cnt = ci+1): step = WIDTH + padding/2.
    final x = ci * (_width + _padding / 2);

    // Stack cards. Upstream item `totalHeight = max(bbox.height +
    // labelPaddingY*2, node.height)` (+ ticket/assigned adjust). The vertical
    // cursor advances by `bbox.height/2 + padding/2` between cards.
    final cardLayout = <_CardLayout>[];
    var y = labelTop; // top of the section box content (== upstream `top`)
    for (final task in col.cards) {
      final titleSz = measurer.measure(task.title, baseStyle, maxWidth: _cardW);
      final ticketSz = (task.ticket != null && task.ticket!.isNotEmpty)
          ? measurer.measure(task.ticket!, baseStyle, maxWidth: _cardW)
          : null;
      final assignedSz = (task.assigned != null && task.assigned!.isNotEmpty)
          ? measurer.measure(task.assigned!, baseStyle, maxWidth: _cardW)
          : null;
      final heightAdj = math.max(
            ticketSz?.height ?? 0,
            assignedSz?.height ?? 0,
          ) /
          2;
      final totalHeight = titleSz.height + _labelPadY * 2 + heightAdj;
      cardLayout.add(_CardLayout(task, titleSz, ticketSz, assignedSz,
          y, totalHeight));
      // Advance cursor: upstream `y = item.y + bbox.height/2 + padding/2`,
      // with `item.y = y + bbox.height/2` ⇒ y += totalHeight + padding/2.
      y += totalHeight + _padding / 2;
    }

    // Section height: max(y - top + 3*padding, 50) + (maxLabelHeight - 25).
    final boxHeight = math.max(y - labelTop + 3 * _padding, 50.0) +
        (maxLabelHeight - _minLabelHeight);

    // Section box: pale theme fill, same color stroke (upstream paints both
    // fill and stroke with `adjuster(cScale, 10)`). rx/ry = 5.
    nodes.add(SceneShape(
      geometry:
          RectGeometry(Rect.fromLTWH(x, labelTop, _width, boxHeight), rx: 5, ry: 5),
      fill: Fill(fill),
      stroke: Stroke(color: fill),
    ));
    // Section label, on top of the box (outside, above), left-aligned to the
    // box top — upstream `clusters.js:kanbanSection` translates the label to
    // `node.y - node.height/2` (the box top).
    final titleSz = titleSizes[ci];
    nodes.add(SceneText(
      text: col.title,
      bounds: Rect.fromLTWH(
          x, labelTop - titleSz.height, _width, titleSz.height),
      style: titleStyle,
      color: _sectionTextColor,
    ));

    // Cards: white fill, neutral nodeBorder stroke (1px), rx/ry = 5.
    for (final card in cardLayout) {
      final cardX = x; // items share the section x (upstream `item.x = section.x`)
      final cardRect = Rect.fromLTWH(cardX, card.y, _cardW, card.totalHeight);
      nodes.add(SceneShape(
        geometry: RectGeometry(cardRect, rx: 5, ry: 5),
        fill: Fill(theme.background),
        stroke: Stroke(color: theme.nodeBorder, width: 1),
      ));

      // Priority bar: a 4px vertical line on the left inner edge.
      final priColor = _colorFromPriority(card.task.priority);
      if (priColor != null) {
        final lineX = cardRect.left + 2;
        final y1 = cardRect.top + (5 ~/ 2); // floor(rx/2), rx = 5
        final y2 = cardRect.bottom - (5 ~/ 2);
        nodes.add(SceneShape(
          geometry: RectGeometry(
              Rect.fromLTWH(lineX - 2, y1, 4, y2 - y1)),
          fill: Fill(priColor),
        ));
      }

      // Title (left-aligned, `padding - totalWidth/2` from center ⇒ left
      // inset of `labelPadX`). Sits in the upper band of the card.
      final hAdj = math.max(
            card.ticketSize?.height ?? 0,
            card.assignedSize?.height ?? 0,
          ) /
          2;
      final titleY = cardRect.top + card.totalHeight / 2 - hAdj -
          card.titleSize.height / 2;
      nodes.add(SceneText(
        text: card.task.title,
        bounds: Rect.fromLTWH(cardRect.left + _labelPadX, titleY,
            _cardW - 2 * _labelPadX, card.titleSize.height),
        style: baseStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ));

      // Ticket label (under the title, left-aligned). Linked when a
      // ticketBaseUrl is configured; the default is empty so it renders as
      // plain underlined link-styled text only when present — here we just
      // render the text left-aligned.
      if (card.ticketSize != null) {
        final ticketY = cardRect.top + card.totalHeight / 2 - hAdj +
            card.titleSize.height / 2 - card.ticketSize!.height / 2;
        nodes.add(SceneText(
          text: card.task.ticket!,
          bounds: Rect.fromLTWH(cardRect.left + _labelPadX, ticketY,
              _cardW - 2 * _labelPadX, card.ticketSize!.height),
          style: baseStyle,
          color: theme.textColor,
          align: TextAlignH.left,
        ));
      }

      // Assigned label (right-aligned, on the same row as the ticket).
      if (card.assignedSize != null) {
        final assignedY = cardRect.top + card.totalHeight / 2 - hAdj +
            card.titleSize.height / 2 - card.assignedSize!.height / 2;
        nodes.add(SceneText(
          text: card.task.assigned!,
          bounds: Rect.fromLTWH(cardRect.left + _labelPadX, assignedY,
              _cardW - 2 * _labelPadX, card.assignedSize!.height),
          style: baseStyle,
          color: theme.textColor,
          align: TextAlignH.right,
        ));
      }
    }
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  const m = 16.0;
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final n in nodes)
        translateSceneNode(n, m - bounds.left, m - bounds.top)
    ],
  );
}

class _CardLayout {
  _CardLayout(this.task, this.titleSize, this.ticketSize, this.assignedSize,
      this.y, this.totalHeight);
  final KanbanTask task;
  final Size titleSize;
  final Size? ticketSize;
  final Size? assignedSize;
  final double y;
  final double totalHeight;
}
