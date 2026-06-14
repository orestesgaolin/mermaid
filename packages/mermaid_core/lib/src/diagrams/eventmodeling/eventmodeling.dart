/// Event modeling (`eventmodeling`): a horizontal timeline of typed frames
/// (ui / cmd / evt / processor / read-model…), laid out in conceptual
/// swimlanes (UI/Automation, Command/Read Model, Events) plus namespace lanes,
/// with inferred / explicit relation arrows between frames.
///
/// Mirrors upstream `db.ts` (swimlane + horizontal-flow layout, relations) and
/// `renderer.ts` (box / swimlane / relation drawing).
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

/// A single frame (`tf`/`timeframe` or `rf`/`resetframe`).
class EmBlock {
  EmBlock(
    this.timeframe,
    this.type,
    this.identifier, {
    this.isReset = false,
    this.sourceFrames = const [],
    this.dataReference,
    this.inlineBody,
  });

  /// Frame id (1–3 digit `EM_FID`), used as a label / cross-reference only.
  final int timeframe;

  /// Canonical (short) entity type: `ui`, `pcr`, `cmd`, `rmo`, `evt`.
  final String type;

  /// Full identifier including optional `namespace.` prefix.
  final String identifier;

  /// `rf`/`resetframe` frames never receive an incoming relation.
  final bool isReset;

  /// Frame ids referenced via `->>`.
  final List<int> sourceFrames;

  /// `[[dataRef]]` reference to a `data` block name.
  final String? dataReference;

  /// Inline `{...}` / quoted body value (raw, braces/quotes stripped).
  final String? inlineBody;

  /// Namespace = text before the single `.`, if any.
  String? get namespace {
    final spl = identifier.split('.');
    return spl.length == 2 ? spl[0] : null;
  }

  /// Display name = text after the single `.`, else the whole identifier.
  String get name {
    final spl = identifier.split('.');
    return spl.length == 2 ? spl[1] : identifier;
  }
}

/// A named `data` block; its body is rendered inside frames that reference it.
class EmDataEntity {
  EmDataEntity(this.name, this.body);
  final String name;
  final String body;
}

class EventModeling {
  const EventModeling(this.blocks, this.dataEntities);
  final List<EmBlock> blocks;
  final List<EmDataEntity> dataEntities;
}

/// Maps a long entity-type keyword to its canonical short form.
const _typeCanonical = {
  'ui': 'ui',
  'pcr': 'pcr',
  'processor': 'pcr',
  'cmd': 'cmd',
  'command': 'cmd',
  'rmo': 'rmo',
  'readmodel': 'rmo',
  'evt': 'evt',
  'event': 'evt',
};

EventModeling parseEventModeling(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  final blocks = <EmBlock>[];
  final dataEntities = <EmDataEntity>[];
  var seenHeader = false;

  final frameRe = RegExp(
    r'^(?:tf|timeframe|rf|resetframe)\s+(\d{1,3})\s+'
    r'(rmo|readmodel|ui|cmd|command|evt|event|pcr|processor)\s+'
    r'([_a-zA-Z][\w]*(?:\.[_a-zA-Z][\w]*)?)\s*'
    r'(.*)$',
  );

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final c = line.indexOf('%%');
    if (c >= 0) line = line.substring(0, c).trim();
    if (line.isEmpty) continue;

    if (!seenHeader) {
      if (!RegExp(r'^eventmodeling\b').hasMatch(line)) {
        throw MermaidParseException('expected "eventmodeling" header',
            line: i + 1);
      }
      seenHeader = true;
      continue;
    }

    // `data <name> { ... multi-line ... }` block.
    final dataHead = RegExp(r'^data\s+([_a-zA-Z][\w]*)\s*\{?\s*$').firstMatch(line);
    if (dataHead != null) {
      final bodyLines = <String>[];
      var j = i + 1;
      // Skip a lone opening brace on its own line (`data Name` then `{`).
      if (!line.contains('{') && j < lines.length && lines[j].trim() == '{') {
        j++;
      }
      for (; j < lines.length; j++) {
        final raw = lines[j];
        if (raw.trim() == '}') break;
        bodyLines.add(raw);
      }
      dataEntities.add(EmDataEntity(dataHead.group(1)!, bodyLines.join('\n')));
      i = j;
      continue;
    }

    // `entity`, `note`, `gwt` declarations are parsed (and currently ignored
    // visually) so they do not break otherwise-valid diagrams.
    if (RegExp(r'^(entity|note|gwt)\b').hasMatch(line)) {
      continue;
    }

    final m = frameRe.firstMatch(line);
    if (m != null) {
      final isReset =
          line.startsWith('rf') || line.startsWith('resetframe');
      final type = _typeCanonical[m.group(2)!] ?? 'evt';
      final rest = m.group(4)!.trim();

      // `->>` source frame references.
      final sources = <int>[];
      for (final sm in RegExp(r'->>\s*(\d{1,3})').allMatches(rest)) {
        sources.add(int.parse(sm.group(1)!));
      }

      // `[[dataRef]]`.
      final dataRefM = RegExp(r'\[\[\s*([_a-zA-Z][\w]*)\s*\]\]').firstMatch(rest);

      // Inline data: `{...}`, "...", or '...' (optionally preceded by
      // a `\`type\`` data-type tag, which we drop).
      String? inline;
      final braceM = RegExp(r'\{(.*)\}', dotAll: true).firstMatch(rest);
      if (braceM != null) {
        inline = braceM.group(1)!.trim();
      } else {
        final quoteM =
            RegExp(r'''(?:"([^"]*)"|'([^']*)')''').firstMatch(rest);
        if (quoteM != null) {
          inline = (quoteM.group(1) ?? quoteM.group(2) ?? '').trim();
        }
      }

      blocks.add(EmBlock(
        int.parse(m.group(1)!),
        type,
        m.group(3)!,
        isReset: isReset,
        sourceFrames: sources,
        dataReference: dataRefM?.group(1),
        inlineBody: inline,
      ));
    }
  }
  if (!seenHeader) {
    throw const MermaidParseException('empty eventmodeling source');
  }
  return EventModeling(blocks, dataEntities);
}

// ---------------------------------------------------------------------------
// Layout constants (upstream `diagramProps` in db.ts).
// ---------------------------------------------------------------------------
const _swimlaneMinHeight = 70.0;
const _swimlanePadding = 15.0;
const _swimlaneGap = 10.0;
const _boxPadding = 10.0;
const _boxOverlap = 90.0;
const _boxMinWidth = 80.0;
const _boxMaxWidth = 450.0;
const _boxMinHeight = 80.0;
const _boxMaxHeight = 750.0;
const _contentStartX = 250.0;
const _textMaxWidth = _boxMaxWidth - 2 * _boxPadding;
const _boxTextPadding = 10.0;
const _emFontSize = 16.0;

const _labelUiAutomation = 'UI/Automation';
const _labelUiAutomationPrefix = 'UI/A: ';
const _labelCommandReadModel = 'Command/Read Model';
const _labelCommandReadModelPrefix = 'C/RM: ';
const _labelEvents = 'Events';
const _labelEventsPrefix = 'Stream: ';

// Entity visual props (upstream `calculateEntityVisualProps`, default theme).
const _entityFill = {
  'ui': Color(0xffffffff),
  'pcr': Color(0xffedb3f6),
  'rmo': Color(0xffd3f1a2),
  'cmd': Color(0xffbcd6fe),
  'evt': Color(0xffffb778),
};
const _entityStroke = {
  'ui': Color(0xffdbdada),
  'pcr': Color(0xffb88cbf),
  'rmo': Color(0xffa3b732),
  'cmd': Color(0xff679ac3),
  'evt': Color(0xffc19a0f),
};

class _Swimlane {
  _Swimlane({required this.index, required this.label, this.namespace});
  final int index;
  String label;
  String? namespace;
  double r = 0;
  double y = 0;
  double height = _swimlaneMinHeight;
  double maxHeight = _swimlaneMinHeight;
}

class _PositionedBox {
  _PositionedBox({
    required this.block,
    required this.x,
    required this.width,
    required this.height,
    required this.swimlane,
    required this.name,
    required this.body,
  });
  final EmBlock block;
  final double x;
  final double width;
  final double height;
  final _Swimlane swimlane;
  final String name;
  final String? body;

  double get r => x + width;
  double get top => swimlane.y + _swimlanePadding;
}

class _Relation {
  _Relation(this.source, this.target);
  final _PositionedBox source;
  final _PositionedBox target;
}

({int index, String label, String? namespace}) _swimlaneProps(
  EmBlock b,
  Map<int, _Swimlane> swimlanes,
) {
  final namespace = b.namespace;
  _Swimlane? sw;
  if (namespace != null && namespace.isNotEmpty) {
    for (final s in swimlanes.values) {
      if (s.namespace == namespace) {
        sw = s;
        break;
      }
    }
  }

  int nextIndex(int lo, int hi) {
    var best = lo;
    for (final k in swimlanes.keys) {
      if (k > lo && k < hi && k > best) best = k;
    }
    return best + 1;
  }

  switch (b.type) {
    case 'ui':
    case 'pcr':
      if (sw != null) {
        return (
          index: sw.index,
          label: sw.namespace ?? _labelUiAutomation,
          namespace: sw.namespace
        );
      } else if (namespace != null) {
        return (
          index: nextIndex(0, 100),
          label: _labelUiAutomationPrefix + namespace,
          namespace: namespace
        );
      }
      return (index: 0, label: _labelUiAutomation, namespace: null);
    case 'rmo':
    case 'cmd':
      if (sw != null) {
        return (
          index: sw.index,
          label: sw.namespace ?? _labelCommandReadModel,
          namespace: sw.namespace
        );
      } else if (namespace != null) {
        return (
          index: nextIndex(100, 200),
          label: _labelCommandReadModelPrefix + namespace,
          namespace: namespace
        );
      }
      return (index: 100, label: _labelCommandReadModel, namespace: null);
    default: // evt
      if (sw != null) {
        return (
          index: sw.index,
          label: sw.namespace ?? _labelEvents,
          namespace: sw.namespace
        );
      } else if (namespace != null) {
        return (
          index: nextIndex(200, 300),
          label: _labelEventsPrefix + namespace,
          namespace: namespace
        );
      }
      return (index: 200, label: _labelEvents, namespace: null);
  }
}

RenderScene layoutEventModeling(
  EventModeling d, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  // Box name: bold 16px trebuchet (upstream wrapLabelConfig).
  final nameStyle = TextStyleSpec(
    fontFamily: theme.fontFamily,
    fontSize: _emFontSize,
    fontWeight: 700,
  );
  // Data body: monospace, left-aligned.
  final bodyStyle = TextStyleSpec(
    fontFamily: 'monospace',
    fontSize: _emFontSize,
  );

  final swimlanes = <int, _Swimlane>{};
  final boxes = <_PositionedBox>[];
  final relations = <_Relation>[];
  final boxByFrameId = <int, _PositionedBox>{};
  double maxR = 0;

  int? previousSwimlaneNumber;

  for (final b in d.blocks) {
    final props = _swimlaneProps(b, swimlanes);
    final swimlane = swimlanes.putIfAbsent(
      props.index,
      () => _Swimlane(
        index: props.index,
        label: props.label,
        namespace: props.namespace,
      ),
    );

    // Resolve body text (inline value wins, else referenced data block).
    String? body = b.inlineBody;
    if (body == null && b.dataReference != null) {
      for (final de in d.dataEntities) {
        if (de.name == b.dataReference) {
          body = de.body;
          break;
        }
      }
    }

    // Measure content to size the box.
    final nameSize =
        measurer.measure(b.name, nameStyle, maxWidth: _textMaxWidth);
    var contentW = nameSize.width;
    var contentH = nameSize.height;
    if (body != null && body.isNotEmpty) {
      final bodySize =
          measurer.measure(body, bodyStyle, maxWidth: _textMaxWidth);
      contentW = contentW > bodySize.width ? contentW : bodySize.width;
      // name + blank gap + body (upstream inserts <br/><br/>).
      contentH += _emFontSize * 2 + bodySize.height;
    }

    final width = _clamp(contentW + 2 * _boxTextPadding, _boxMinWidth,
            _boxMaxWidth) +
        2 * _boxPadding;
    final height = _clamp(contentH + 2 * _boxTextPadding, _boxMinHeight,
            _boxMaxHeight) +
        2 * _boxPadding;

    // Horizontal flow (calculateX).
    final lastBox = boxes.isNotEmpty ? boxes.last : null;
    final previousSwimlane = previousSwimlaneNumber != null
        ? swimlanes[previousSwimlaneNumber]
        : null;
    final double x;
    if (previousSwimlane == null) {
      x = _contentStartX;
    } else if (previousSwimlane.index == swimlane.index && swimlane.r != 0) {
      x = swimlane.r + _boxPadding;
    } else if (lastBox == null) {
      x = _contentStartX;
    } else {
      x = lastBox.r - _boxOverlap + _boxPadding;
    }

    final r = x + width + _boxPadding;
    maxR = [for (final s in swimlanes.values) s.r, r, maxR]
        .reduce((a, c) => a > c ? a : c);

    swimlane.r = x + width;
    swimlane.maxHeight =
        swimlane.maxHeight > height ? swimlane.maxHeight : height;
    swimlane.height = (swimlane.maxHeight > _swimlaneMinHeight
            ? swimlane.maxHeight
            : _swimlaneMinHeight) +
        2 * _swimlanePadding;

    final box = _PositionedBox(
      block: b,
      x: x,
      width: width,
      height: height,
      swimlane: swimlane,
      name: b.name,
      body: (body != null && body.isNotEmpty) ? body : null,
    );
    boxes.add(box);
    boxByFrameId[b.timeframe] = box;
    previousSwimlaneNumber = swimlane.index;

    // Recompute swimlane y stacking top-down.
    final sorted = swimlanes.values.toList()
      ..sort((a, c) => a.index.compareTo(c.index));
    if (sorted.isNotEmpty) sorted[0].y = 0;
    for (var i = 1; i < sorted.length; i++) {
      sorted[i].y = sorted[i - 1].y + sorted[i - 1].height + _swimlaneGap;
    }
  }

  // Relations (decidePositionRelation): for each frame after the first,
  // connect from its source frame(s) (explicit `->>` or the previous box in a
  // different swimlane) to this box. Reset frames and the first frame get none.
  for (var idx = 0; idx < boxes.length; idx++) {
    final target = boxes[idx];
    final b = target.block;
    if (b.isReset) continue;
    if (idx == 0 && b.sourceFrames.isEmpty) continue;

    if (b.sourceFrames.isNotEmpty) {
      for (final sf in b.sourceFrames) {
        final src = boxByFrameId[sf];
        if (src != null) relations.add(_Relation(src, target));
      }
    } else {
      // findBoxByLineIndex: walk back from idx-1 to the first box in a
      // different swimlane.
      _PositionedBox? src;
      for (var i = idx - 1; i >= 0; i--) {
        if (boxes[i].swimlane.index != target.swimlane.index) {
          src = boxes[i];
          break;
        }
      }
      if (src != null) relations.add(_Relation(src, target));
    }
  }

  final nodes = <SceneNode>[];

  // Swimlane bands + labels (renderD3Swimlane).
  final sortedSwimlanes = swimlanes.values.toList()
    ..sort((a, c) => a.index.compareTo(c.index));
  for (final s in sortedSwimlanes) {
    nodes.add(SceneShape(
      geometry: RectGeometry(
        Rect.fromLTWH(0, s.y, maxR + _swimlanePadding, s.height),
        rx: 3,
        ry: 3,
      ),
      fill: const Fill(Color(0xfffafafa)), // rgb(250,250,250)
      stroke: const Stroke(color: Color(0xfff0f0f0)), // rgb(240,240,240)
    ));
    final labelSize = measurer.measure(s.label, nameStyle);
    nodes.add(SceneText(
      text: s.label,
      bounds: Rect.fromLTWH(
          30, s.y + 30 - labelSize.height, labelSize.width, labelSize.height),
      style: nameStyle,
      color: theme.textColor,
      align: TextAlignH.left,
    ));
  }

  // Boxes (renderD3Box).
  for (final box in boxes) {
    final y = box.top;
    nodes.add(SceneShape(
      geometry: RectGeometry(
        Rect.fromLTWH(box.x, y, box.width, box.height),
        rx: 3,
        ry: 3,
      ),
      fill: Fill(_entityFill[box.block.type] ?? const Color(0xffff0000)),
      stroke: Stroke(color: _entityStroke[box.block.type] ?? Color.black),
    ));

    final innerW = box.width - 2 * _boxPadding;
    if (box.body == null) {
      // Centered bold name.
      final ns = measurer.measure(box.name, nameStyle, maxWidth: innerW);
      nodes.add(SceneText(
        text: box.name,
        bounds: Rect.fromCenter(
            Point(box.x + box.width / 2, y + box.height / 2),
            ns.width,
            ns.height),
        style: nameStyle,
        color: theme.textColor,
        align: TextAlignH.center,
      ));
    } else {
      // Bold name centered near the top, then a left-aligned monospace body.
      final ns = measurer.measure(box.name, nameStyle, maxWidth: innerW);
      final bs = measurer.measure(box.body!, bodyStyle, maxWidth: innerW);
      final contentTop = y + _boxPadding + _boxTextPadding;
      nodes.add(SceneText(
        text: box.name,
        bounds: Rect.fromLTWH(
            box.x + box.width / 2 - ns.width / 2, contentTop, ns.width, ns.height),
        style: nameStyle,
        color: theme.textColor,
        align: TextAlignH.center,
      ));
      nodes.add(SceneText(
        text: box.body!,
        bounds: Rect.fromLTWH(box.x + _boxPadding + _boxTextPadding,
            contentTop + ns.height + _emFontSize, innerW, bs.height),
        style: bodyStyle,
        color: theme.textColor,
        align: TextAlignH.left,
      ));
    }
  }

  // Relations (renderD3Relation): straight path + triangle arrowhead.
  for (final rel in relations) {
    final src = rel.source;
    final tgt = rel.target;
    final upwards = src.top > tgt.top;

    final sourceX = src.x + src.width * 2 / 3;
    final targetX = tgt.x + tgt.width / 3;

    final double sourceY;
    final double targetY;
    if (upwards) {
      sourceY = src.top;
      targetY = tgt.top + tgt.height;
    } else {
      sourceY = src.top + src.height;
      targetY = tgt.top;
    }

    nodes.add(SceneShape(
      geometry: PathGeometry([
        MoveTo(Point(sourceX, sourceY)),
        LineTo(Point(targetX, targetY)),
      ]),
      stroke: const Stroke(color: Color(0xff000000)),
    ));

    // Triangle arrowhead (polygon "0 0, 10 3.5, 0 7", refX=10) pointing along
    // the path direction toward the target.
    final dx = targetX - sourceX;
    final dy = targetY - sourceY;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0) {
      final ux = dx / len;
      final uy = dy / len;
      final tip = Point(targetX, targetY);
      final base = Point(targetX - ux * 10, targetY - uy * 10);
      final perp = Point(-uy, ux);
      nodes.add(SceneShape(
        geometry: PolygonGeometry([
          tip,
          base + perp * 3.5,
          base - perp * 3.5,
        ]),
        fill: const Fill(Color(0xff000000)),
      ));
    }
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 200, 100);
  const m = 30.0; // config.padding ?? 30
  return RenderScene(
    size: Size(bounds.width + 2 * m, bounds.height + 2 * m),
    background: theme.background,
    nodes: [
      for (final n in nodes)
        translateSceneNode(n, m - bounds.left, m - bounds.top)
    ],
  );
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);
