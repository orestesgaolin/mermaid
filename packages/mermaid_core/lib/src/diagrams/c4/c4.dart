/// C4 diagrams (C4Context / C4Container / C4Component / C4Dynamic):
/// model, parser and layout — one file.
///
/// Reference: upstream c4 jison grammar + c4Renderer. Upstream uses a bespoke
/// row-packing grid (shapes packed left-to-right, wrapping after
/// `c4ShapeInRow`=4; boundaries `c4BoundaryInRow`=2 per row). This port mirrors
/// that packing rather than a rank layout.
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

/// The C4 diagram subtype (header keyword). Drives C4Dynamic auto-numbering.
enum C4Subtype { context, container, component, dynamic, deployment }

class C4Diagram {
  const C4Diagram({
    required this.nodes,
    required this.boundaries,
    required this.rels,
    this.title,
    this.subtype = C4Subtype.context,
  });

  final Map<String, C4Node> nodes;
  final List<C4Boundary> boundaries;
  final List<C4Rel> rels;
  final String? title;
  final C4Subtype subtype;
}

enum C4Kind { person, personExt, system, systemExt, container, component, db, queue }

class C4Node {
  const C4Node({
    required this.id,
    required this.kind,
    required this.label,
    this.description = '',
    this.technology = '',
    this.external = false,
    this.boundary,
    this.bgColor,
    this.fontColor,
    this.borderColor,
  });

  final String id;
  final C4Kind kind;
  final String label;
  final String description;
  final String technology;

  /// True for any `*_Ext` element (incl. ext db/queue, which collapse into the
  /// [C4Kind.db]/[C4Kind.queue] kinds but keep their external gray coloring).
  final bool external;
  final String? boundary;

  /// `UpdateElementStyle` overrides ($bgColor / $fontColor / $borderColor).
  final Color? bgColor;
  final Color? fontColor;
  final Color? borderColor;

  C4Node copyWith({Color? bgColor, Color? fontColor, Color? borderColor}) =>
      C4Node(
        id: id,
        kind: kind,
        label: label,
        description: description,
        technology: technology,
        external: external,
        boundary: boundary,
        bgColor: bgColor ?? this.bgColor,
        fontColor: fontColor ?? this.fontColor,
        borderColor: borderColor ?? this.borderColor,
      );
}

class C4Boundary {
  const C4Boundary({
    required this.id,
    required this.label,
    this.type = '',
    this.description = '',
    this.parent,
    this.bgColor,
    this.borderColor,
    this.fontColor,
  });

  final String id;
  final String label;
  final String type;
  final String description;
  final String? parent;

  /// `UpdateBoundaryStyle` overrides ($bgColor / $borderColor / $fontColor).
  final Color? bgColor;
  final Color? borderColor;
  final Color? fontColor;

  C4Boundary copyWith({
    Color? bgColor,
    Color? borderColor,
    Color? fontColor,
  }) =>
      C4Boundary(
        id: id,
        label: label,
        type: type,
        description: description,
        parent: parent,
        bgColor: bgColor ?? this.bgColor,
        borderColor: borderColor ?? this.borderColor,
        fontColor: fontColor ?? this.fontColor,
      );
}

class C4Rel {
  const C4Rel({
    required this.from,
    required this.to,
    required this.label,
    this.technology = '',
    this.bidirectional = false,
    this.backwards = false,
    this.textColor,
    this.lineColor,
  });

  final String from;
  final String to;
  final String label;
  final String technology;
  final bool bidirectional;

  /// `Rel_Back`: start marker only, no end marker.
  final bool backwards;

  /// `UpdateRelStyle` overrides ($textColor / $lineColor).
  final Color? textColor;
  final Color? lineColor;

  C4Rel copyWith({Color? textColor, Color? lineColor}) => C4Rel(
        from: from,
        to: to,
        label: label,
        technology: technology,
        bidirectional: bidirectional,
        backwards: backwards,
        textColor: textColor ?? this.textColor,
        lineColor: lineColor ?? this.lineColor,
      );
}

C4Diagram parseC4Diagram(String source) {
  final frontTitle = frontmatterTitle(source);
  final text = stripMetadata(source);
  final nodes = <String, C4Node>{};
  final boundaries = <C4Boundary>[];
  final rels = <C4Rel>[];
  String? title = frontTitle;
  var seenHeader = false;
  var subtype = C4Subtype.context;
  final boundaryStack = <String>[];

  // Split on commas outside quotes; returns the raw (still-quoted) tokens.
  List<String> rawArgs(String s) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuote = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') inQuote = !inQuote;
      if (c == ',' && !inQuote) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }

  String unquote(String a) {
    a = a.trim();
    if (a.length >= 2 && a.startsWith('"') && a.endsWith('"')) {
      a = a.substring(1, a.length - 1);
    }
    return a.replaceAll('<br/>', '\n').replaceAll('<br>', '\n');
  }

  List<String> args(String s) => [for (final a in rawArgs(s)) unquote(a)];

  // Positional args only: drops `$key=value` named args (e.g. $sprite, $tags,
  // $link, $type) so trailing/extra named args don't get mistaken for
  // label/desc/tech. Tested against the raw token so a quoted value such as
  // "$5 / item" is never dropped.
  final namedArg = RegExp(r'^\$\w+\s*=');
  List<String> positional(String s) =>
      [for (final a in rawArgs(s)) if (!namedArg.hasMatch(a.trim())) unquote(a)];

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment).trim();
    if (line.isEmpty) continue;
    if (!seenHeader) {
      final h = RegExp(r'^C4(Context|Container|Component|Dynamic|Deployment)\b')
          .firstMatch(line);
      if (h == null) {
        throw MermaidParseException('expected a C4 header', line: i + 1);
      }
      subtype = switch (h.group(1)!) {
        'Container' => C4Subtype.container,
        'Component' => C4Subtype.component,
        'Dynamic' => C4Subtype.dynamic,
        'Deployment' => C4Subtype.deployment,
        _ => C4Subtype.context,
      };
      seenHeader = true;
      continue;
    }
    Match? m;
    m = RegExp(r'^title\s+(.+)$').firstMatch(line);
    if (m != null) {
      title = m.group(1)!.trim();
      continue;
    }
    if (line == '}') {
      if (boundaryStack.isEmpty) {
        throw MermaidParseException('"}" without open boundary', line: i + 1);
      }
      boundaryStack.removeLast();
      continue;
    }
    // Boundary(id, "label" [, "type"]) {
    m = RegExp(
            r'^(Enterprise_Boundary|System_Boundary|Container_Boundary|Boundary|Deployment_Node|Node|Node_L|Node_R)\s*\((.*)\)\s*\{$')
        .firstMatch(line);
    if (m != null) {
      final fn = m.group(1)!;
      final a = positional(m.group(2)!);
      final id = a[0];
      // Upstream default boundary type per keyword (drawn as a `[type]` line).
      final defaultType = switch (fn) {
        'Enterprise_Boundary' => 'Enterprise',
        'System_Boundary' => 'System',
        'Container_Boundary' => 'Container',
        'Deployment_Node' || 'Node' || 'Node_L' || 'Node_R' => 'Node',
        _ => '',
      };
      boundaries.add(C4Boundary(
        id: id,
        label: a.length > 1 ? a[1] : id,
        type: a.length > 2 ? a[2] : defaultType,
        description: a.length > 3 ? a[3] : '',
        parent: boundaryStack.isEmpty ? null : boundaryStack.last,
      ));
      boundaryStack.add(id);
      continue;
    }
    // Element: Kind(id, "label" [, "description"/"technology" ...])
    m = RegExp(r'^(\w+)\s*\((.*)\)\s*$').firstMatch(line);
    if (m != null) {
      final fn = m.group(1)!;
      // `a` for the Update* handlers keeps the $key=value tokens; element/rel
      // parsing uses `p` which drops them (sprite/tags/link tolerance).
      final a = args(m.group(2)!);
      final p = positional(m.group(2)!);
      final isExt = fn.contains('_Ext');
      C4Kind? kind = switch (fn) {
        'Person' => C4Kind.person,
        'Person_Ext' => C4Kind.personExt,
        'System' || 'SystemDb' || 'SystemQueue' || 'System_Ext' ||
        'SystemDb_Ext' || 'SystemQueue_Ext' =>
          fn.startsWith('SystemDb')
              ? C4Kind.db
              : (fn.startsWith('SystemQueue')
                  ? C4Kind.queue
                  : (isExt ? C4Kind.systemExt : C4Kind.system)),
        'Container' || 'ContainerDb' || 'ContainerQueue' ||
        'Container_Ext' || 'ContainerDb_Ext' || 'ContainerQueue_Ext' =>
          fn.startsWith('ContainerDb')
              ? C4Kind.db
              : (fn.startsWith('ContainerQueue') ? C4Kind.queue : C4Kind.container),
        'Component' || 'ComponentDb' || 'ComponentQueue' ||
        'Component_Ext' || 'ComponentDb_Ext' || 'ComponentQueue_Ext' =>
          fn.startsWith('ComponentDb')
              ? C4Kind.db
              : (fn.startsWith('ComponentQueue') ? C4Kind.queue : C4Kind.component),
        _ => null,
      };
      if (kind != null) {
        if (p.isEmpty) {
          throw MermaidParseException('$fn needs arguments', line: i + 1);
        }
        final hasTechn =
            fn.startsWith('Container') || fn.startsWith('Component');
        nodes[p[0]] = C4Node(
          id: p[0],
          kind: kind,
          label: p.length > 1 ? p[1] : p[0],
          external: isExt,
          technology: hasTechn && p.length > 2 ? p[2] : '',
          description: p.length > (hasTechn ? 3 : 2)
              ? p.last
              : (p.length > 2 && !hasTechn ? p[2] : ''),
          boundary: boundaryStack.isEmpty ? null : boundaryStack.last,
        );
        continue;
      }
      // Rel(from, to, "label" [, "technology"]) and directional variants.
      if (RegExp(r'^(Bi)?Rel(_[UDLR]|_Up|_Down|_Left|_Right|_Back)?$')
          .hasMatch(fn)) {
        if (p.length < 2) {
          throw MermaidParseException('$fn needs two endpoints', line: i + 1);
        }
        rels.add(C4Rel(
          from: p[0],
          to: p[1],
          label: p.length > 2 ? p[2] : '',
          technology: p.length > 3 ? p[3] : '',
          bidirectional: fn.startsWith('BiRel'),
          backwards: fn == 'Rel_Back',
        ));
        continue;
      }
      // UpdateElementStyle(id, $bgColor=, $fontColor=, $borderColor=).
      if (fn == 'UpdateElementStyle' && a.isNotEmpty) {
        final kv = _styleArgs(a.skip(1));
        final id = a[0];
        final node = nodes[id];
        if (node != null) {
          nodes[id] = node.copyWith(
            bgColor: Color.tryParse(kv['bgColor'] ?? ''),
            fontColor: Color.tryParse(kv['fontColor'] ?? ''),
            borderColor: Color.tryParse(kv['borderColor'] ?? ''),
          );
        }
        continue;
      }
      // UpdateBoundaryStyle(id, $bgColor=, $borderColor=, $fontColor=).
      if (fn == 'UpdateBoundaryStyle' && a.isNotEmpty) {
        final kv = _styleArgs(a.skip(1));
        final id = a[0];
        for (var b = 0; b < boundaries.length; b++) {
          if (boundaries[b].id == id) {
            boundaries[b] = boundaries[b].copyWith(
              bgColor: Color.tryParse(kv['bgColor'] ?? ''),
              borderColor: Color.tryParse(kv['borderColor'] ?? ''),
              fontColor: Color.tryParse(kv['fontColor'] ?? ''),
            );
          }
        }
        continue;
      }
      // UpdateRelStyle(from, to, $textColor=, $lineColor=, ...).
      if (fn == 'UpdateRelStyle' && a.length >= 2) {
        final kv = _styleArgs(a.skip(2));
        for (var r = 0; r < rels.length; r++) {
          if (rels[r].from == a[0] && rels[r].to == a[1]) {
            rels[r] = rels[r].copyWith(
              textColor: Color.tryParse(kv['textColor'] ?? ''),
              lineColor: Color.tryParse(kv['lineColor'] ?? ''),
            );
          }
        }
        continue;
      }
      // Other Update* / LAYOUT hints: ignored.
      if (fn.startsWith('Update') || fn.toUpperCase().startsWith('LAYOUT')) {
        continue;
      }
    }
    if (RegExp(r'^acc(Title|Descr)\s*[:{]').hasMatch(line)) continue;
    throw MermaidParseException('unrecognized statement "$line"', line: i + 1);
  }
  if (!seenHeader) {
    throw const MermaidParseException('empty C4 source');
  }
  return C4Diagram(
      nodes: nodes,
      boundaries: boundaries,
      rels: rels,
      title: title,
      subtype: subtype);
}

/// Parses `$key="value"` / `$key=value` style args into a map (key without
/// the leading `$`).
Map<String, String> _styleArgs(Iterable<String> args) {
  final out = <String, String>{};
  for (final a in args) {
    final m = RegExp(r'^\$?(\w+)\s*=\s*(.*)$').firstMatch(a.trim());
    if (m != null) {
      var v = m.group(2)!.trim();
      if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
        v = v.substring(1, v.length - 1);
      }
      out[m.group(1)!] = v;
    }
  }
  return out;
}

// Upstream C4 default colors (config.schema.yaml `c4` block). Each kind has a
// distinct fill and border; external kinds use distinct grays.
const _white = Color(0xffffffff);

({Color fill, Color border}) _kindColors(C4Node n) {
  if (n.external) {
    return switch (n.kind) {
      C4Kind.personExt || C4Kind.person =>
        (fill: Color(0xff686868), border: Color(0xff8a8a8a)),
      C4Kind.systemExt || C4Kind.system || C4Kind.db || C4Kind.queue =>
        (fill: Color(0xff999999), border: Color(0xff8a8a8a)),
      C4Kind.container =>
        (fill: Color(0xffb3b3b3), border: Color(0xffa6a6a6)),
      C4Kind.component =>
        (fill: Color(0xffcccccc), border: Color(0xffbfbfbf)),
    };
  }
  return switch (n.kind) {
    C4Kind.person => (fill: Color(0xff08427b), border: Color(0xff073b6f)),
    C4Kind.personExt => (fill: Color(0xff686868), border: Color(0xff8a8a8a)),
    C4Kind.systemExt => (fill: Color(0xff999999), border: Color(0xff8a8a8a)),
    C4Kind.system || C4Kind.db || C4Kind.queue =>
      (fill: Color(0xff1168bd), border: Color(0xff3c7fc0)),
    C4Kind.container =>
      (fill: Color(0xff438dd5), border: Color(0xff3c7fc0)),
    C4Kind.component =>
      (fill: Color(0xff85bbf0), border: Color(0xff78a8d8)),
  };
}

/// Upstream stereotype keyword drawn as `<<...>>` above the label.
String _stereotype(C4Node n) {
  final base = switch (n.kind) {
    C4Kind.person => 'person',
    C4Kind.personExt => 'external_person',
    C4Kind.system => 'system',
    C4Kind.systemExt => 'external_system',
    C4Kind.container => 'container',
    C4Kind.component => 'component',
    C4Kind.db => 'database',
    C4Kind.queue => 'queue',
  };
  return '<<$base>>';
}

// Upstream c4 layout constants (config.schema.yaml `c4` block).
const _confWidth = 216.0;
const _confHeight = 60.0;
const _shapePadding = 20.0;
const _shapeMargin = 50.0;
const _c4ShapeInRow = 4;
const _c4BoundaryInRow = 2;
const _diagramMarginX = 50.0;
const _diagramMarginY = 10.0;

// A laid-out shape rectangle plus its precomputed text blocks.
class _ShapeBox {
  _ShapeBox(this.size, this.stereo, this.label, this.techn, this.desc);
  final Size size;
  final Size stereo;
  final Size label;
  final Size techn;
  final Size desc;
  late double x;
  late double y;
}

RenderScene layoutC4Diagram(
  C4Diagram diagram, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const pad = 12.0;
  // Stereotype line: fontSize-2, italic. Label: bold, fontSize+2. Techn line:
  // italic fontSize. Descr (personFont): normal fontSize.
  final stereoStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: theme.fontSize - 2, italic: true);
  final labelStyle = TextStyleSpec(
      fontFamily: theme.fontFamily,
      fontSize: theme.fontSize + 2,
      fontWeight: 700);
  final technStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: theme.fontSize, italic: true);
  final descStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final relStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);
  final boundaryLabelStyle = TextStyleSpec(
      fontFamily: theme.fontFamily,
      fontSize: theme.fontSize + 2,
      fontWeight: 700);
  final boundaryTypeStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: theme.fontSize);

  final textLimit = _confWidth - _shapePadding * 2;

  // Measure each shape and compute its box (min 216x60, grows to content).
  final boxes = <String, _ShapeBox>{};
  for (final n in diagram.nodes.values) {
    final stereo = measurer.measure(_stereotype(n), stereoStyle);
    final label = measurer.measure(n.label, labelStyle, maxWidth: textLimit);
    final techn = n.technology.isEmpty
        ? Size.zero
        : measurer.measure('[${n.technology}]', technStyle,
            maxWidth: textLimit);
    final desc = n.description.isEmpty
        ? Size.zero
        : measurer.measure(n.description, descStyle, maxWidth: textLimit);
    final isPerson = n.kind == C4Kind.person || n.kind == C4Kind.personExt;
    final imageH = isPerson ? 48.0 : 0.0;
    final contentW = [stereo.width, label.width, techn.width, desc.width]
        .reduce(math.max);
    final w = math.max(_confWidth, contentW + _shapePadding * 2);
    final contentH = _shapePadding + // top padding above stereotype
        stereo.height +
        imageH +
        8 +
        label.height +
        (techn.height > 0 ? techn.height + 5 : 0) +
        (desc.height > 0 ? desc.height + 20 : 0) +
        _shapePadding;
    final h = math.max(_confHeight, contentH);
    boxes[n.id] = _ShapeBox(Size(w, h), stereo, label, techn, desc);
  }

  // ---- Row-packing layout (mirrors Bounds.insert / drawInsideBoundary). ----
  // Children of a given boundary (null = top level), preserving insertion order.
  final boundaryById = {for (final b in diagram.boundaries) b.id: b};
  final childBoundaries = <String?, List<C4Boundary>>{};
  for (final b in diagram.boundaries) {
    childBoundaries.putIfAbsent(b.parent, () => []).add(b);
  }
  final childNodes = <String?, List<C4Node>>{};
  for (final n in diagram.nodes.values) {
    childNodes.putIfAbsent(n.boundary, () => []).add(n);
  }

  final placedRects = <String, Rect>{}; // node id -> rect (absolute)
  final boundaryRects = <String, Rect>{};

  // Lays out a container's direct member shapes in rows of c4ShapeInRow,
  // starting at (originX, originY); returns the bounding rect of the packed
  // shapes (or null if none). Shapes are placed absolutely into placedRects.
  Rect? packShapes(List<C4Node> shapes, double originX, double originY) {
    if (shapes.isEmpty) return null;
    double startx = originX, stopx = originX, starty = originY, stopy = originY;
    double minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    var cnt = 0;
    for (final n in shapes) {
      final box = boxes[n.id]!;
      cnt += 1;
      var sx = (startx == stopx)
          ? stopx + _shapeMargin
          : stopx + _shapeMargin * 2;
      var sy = starty + _shapeMargin * 2;
      if (cnt > _c4ShapeInRow) {
        sx = startx + _shapeMargin;
        sy = stopy + _shapeMargin * 2;
        starty = stopy;
        cnt = 1;
      }
      final ex = sx + box.size.width;
      final ey = sy + box.size.height;
      box.x = sx;
      box.y = sy;
      placedRects[n.id] = Rect.fromLTWH(sx, sy, box.size.width, box.size.height);
      startx = math.min(startx, sx);
      starty = math.min(starty, sy);
      stopx = math.max(stopx, ex);
      stopy = math.max(stopy, ey);
      minX = math.min(minX, sx);
      minY = math.min(minY, sy);
      maxX = math.max(maxX, ex);
      maxY = math.max(maxY, ey);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // Recursively lays out a boundary's contents (shapes + nested boundaries),
  // starting at (originX, originY). Returns the inner content rect.
  Rect? layoutContainer(String? boundaryId, double originX, double originY) {
    Rect? acc;
    void include(Rect r) => acc = acc == null ? r : acc!.union(r);

    final shapes = childNodes[boundaryId] ?? const [];
    final shapeRect = packShapes(shapes, originX, originY);
    if (shapeRect != null) include(shapeRect);

    final subs = childBoundaries[boundaryId] ?? const [];
    if (subs.isNotEmpty) {
      // Boundaries are laid out c4BoundaryInRow per row, below the shapes.
      var rowStartY = (acc?.bottom ?? originY) +
          (shapeRect != null ? _shapeMargin : 0);
      var x = originX + _diagramMarginX;
      var rowMaxBottom = rowStartY;
      for (var bi = 0; bi < subs.length; bi++) {
        if (bi != 0 && bi % _c4BoundaryInRow == 0) {
          // New row of boundaries.
          rowStartY = rowMaxBottom + _diagramMarginY + _shapeMargin;
          x = originX + _diagramMarginX;
          rowMaxBottom = rowStartY;
        }
        final inner = layoutContainer(
            subs[bi].id, x + 14, rowStartY + 14 + 24);
        Rect rect;
        if (inner == null) {
          rect = Rect.fromLTWH(x, rowStartY, _confWidth, _confHeight);
        } else {
          rect = Rect.fromLTRB(
              inner.left - 14, inner.top - 14 - 24, inner.right + 14,
              inner.bottom + 14);
        }
        boundaryRects[subs[bi].id] = rect;
        include(rect);
        x = rect.right + _diagramMarginX;
        rowMaxBottom = math.max(rowMaxBottom, rect.bottom);
      }
    }
    return acc;
  }

  layoutContainer(null, _diagramMarginX, _diagramMarginY);

  // Resolve final centers from placed rects.
  final centers = <String, Point>{};
  diagram.nodes.forEach((id, _) {
    final r = placedRects[id];
    if (r != null) centers[id] = r.center;
  });

  final clusterNodes = <SceneNode>[];
  final edgeNodes = <SceneNode>[];
  final labelNodes = <SceneNode>[];
  final elementNodes = <SceneNode>[];

  // ---- Boundaries (outermost first so nested ones paint on top). ----
  final orderedBoundaries = diagram.boundaries
      .where((b) => boundaryRects.containsKey(b.id))
      .toList()
    ..sort((a, b) {
      int depth(C4Boundary x) {
        var d = 0;
        var p = x.parent;
        while (p != null) {
          d++;
          p = boundaryById[p]?.parent;
        }
        return d;
      }

      return depth(a).compareTo(depth(b));
    });
  for (final b in orderedBoundaries) {
    final rect = boundaryRects[b.id]!;
    final borderColor = b.borderColor ?? const Color(0xff444444);
    final fontColor = b.fontColor ?? const Color(0xff444444);
    final children = <SceneNode>[
      SceneShape(
        geometry: RectGeometry(rect, rx: 2.5, ry: 2.5),
        fill: b.bgColor != null ? Fill(b.bgColor!) : null,
        stroke: Stroke(color: borderColor, dash: const [7, 7]),
      ),
    ];
    // Label near the top of the cluster rect (upstream label.Y).
    final labelSize = measurer.measure(b.label, boundaryLabelStyle);
    var ty = rect.top + 6;
    children.add(SceneText(
      text: b.label,
      bounds: Rect.fromLTWH(
          rect.center.x - labelSize.width / 2, ty, labelSize.width,
          labelSize.height),
      style: boundaryLabelStyle,
      color: fontColor,
    ));
    ty += labelSize.height + 2;
    if (b.type.isNotEmpty) {
      final s = measurer.measure('[${b.type}]', boundaryTypeStyle);
      children.add(SceneText(
        text: '[${b.type}]',
        bounds: Rect.fromLTWH(
            rect.center.x - s.width / 2, ty, s.width, s.height),
        style: boundaryTypeStyle,
        color: fontColor,
      ));
      ty += s.height + 2;
    }
    if (b.description.isNotEmpty) {
      final s = measurer.measure(b.description, boundaryTypeStyle,
          maxWidth: rect.width - 16);
      children.add(SceneText(
        text: b.description,
        bounds: Rect.fromLTWH(
            rect.center.x - s.width / 2, ty, s.width, s.height),
        style: boundaryTypeStyle,
        color: fontColor,
      ));
    }
    clusterNodes.add(SceneGroup(id: 'boundary_${b.id}', children: children));
  }

  // ---- Relations ----
  for (var i = 0; i < diagram.rels.length; i++) {
    final r = diagram.rels[i];
    if (!centers.containsKey(r.from) || !centers.containsKey(r.to)) continue;
    final fromRect = placedRects[r.from]!;
    final toRect = placedRects[r.to]!;
    final start = _intersectRect(fromRect, toRect.center);
    var end = _intersectRect(toRect, fromRect.center);
    final dir = _dir(start, end);
    final tip = end;
    end = tip - dir * 9;
    final perp = Point(-dir.y, dir.x);
    final lineCol = r.lineColor ?? const Color(0xff444444);

    final children = <SceneNode>[
      SceneShape(
        geometry: PathGeometry([MoveTo(start), LineTo(end)]),
        stroke: Stroke(color: lineCol, width: 1),
      ),
    ];
    // End arrowhead unless Rel_Back.
    if (!r.backwards) {
      children.add(SceneShape(
        geometry: PolygonGeometry(
            [tip, tip - dir * 10 + perp * 4.5, tip - dir * 10 - perp * 4.5]),
        fill: Fill(lineCol),
      ));
    }
    // Start arrowhead for BiRel / Rel_Back.
    if (r.bidirectional || r.backwards) {
      final sdir = _dir(end, start);
      final sperp = Point(-sdir.y, sdir.x);
      children.add(SceneShape(
        geometry: PolygonGeometry([
          start,
          start - sdir * 10 + sperp * 4.5,
          start - sdir * 10 - sperp * 4.5,
        ]),
        fill: Fill(lineCol),
      ));
    }
    edgeNodes.add(SceneGroup(
        id: 'rel_${r.from}_${r.to}_$i',
        semanticLabel: r.label,
        children: children));

    // Label at the midpoint (no background rect; C4Dynamic auto-numbers).
    final textColor = r.textColor ?? const Color(0xff444444);
    final labelText = diagram.subtype == C4Subtype.dynamic
        ? '${i + 1}: ${r.label}'
        : r.label;
    final mid = Point((start.x + tip.x) / 2, (start.y + tip.y) / 2);
    if (labelText.isNotEmpty) {
      final size = measurer.measure(labelText, relStyle, maxWidth: 150);
      labelNodes.add(SceneText(
        text: labelText,
        bounds: Rect.fromCenter(mid, size.width, size.height),
        style: relStyle,
        color: textColor,
      ));
      if (r.technology.isNotEmpty) {
        final ts = measurer.measure('[${r.technology}]', technStyle,
            maxWidth: 150);
        labelNodes.add(SceneText(
          text: '[${r.technology}]',
          bounds: Rect.fromCenter(
              Point(mid.x, mid.y + size.height / 2 + ts.height / 2 + 2),
              ts.width, ts.height),
          style: technStyle,
          color: textColor,
        ));
      }
    } else if (r.technology.isNotEmpty) {
      final ts =
          measurer.measure('[${r.technology}]', technStyle, maxWidth: 150);
      labelNodes.add(SceneText(
        text: '[${r.technology}]',
        bounds: Rect.fromCenter(mid, ts.width, ts.height),
        style: technStyle,
        color: textColor,
      ));
    }
  }

  // ---- Element shapes ----
  diagram.nodes.forEach((id, n) {
    final box = boxes[id]!;
    final rect = placedRects[id]!;
    final colors = _kindColors(n);
    final fill = n.bgColor ?? colors.fill;
    final border = n.borderColor ?? colors.border;
    final labelColor = n.fontColor ?? _white;
    final isPerson = n.kind == C4Kind.person || n.kind == C4Kind.personExt;

    final children = <SceneNode>[];
    // Shape geometry: rect / cylinder (db) / queue (pill).
    switch (n.kind) {
      case C4Kind.db:
        children.add(SceneShape(
          geometry: _cylinderPath(rect),
          fill: Fill(fill),
          stroke: Stroke(color: border, width: 0.5),
        ));
      case C4Kind.queue:
        children.add(SceneShape(
          geometry: _queuePath(rect),
          fill: Fill(fill),
          stroke: Stroke(color: border, width: 0.5),
        ));
      default:
        children.add(SceneShape(
          geometry: RectGeometry(rect, rx: 2.5, ry: 2.5),
          fill: Fill(fill),
          stroke: Stroke(color: border, width: 0.5),
        ));
    }

    // Stacked text: stereotype, [avatar], label, techn, descr.
    var y = rect.top + _shapePadding;
    children.add(SceneText(
      text: _stereotype(n),
      bounds: Rect.fromLTWH(rect.center.x - box.stereo.width / 2, y,
          box.stereo.width, box.stereo.height),
      style: stereoStyle,
      color: labelColor,
    ));
    y += box.stereo.height;
    if (isPerson) {
      // Upstream draws a 48x48 base64 avatar here. Without a raster-image IR
      // primitive we approximate it with a head+shoulders silhouette.
      final cx = rect.center.x;
      final headR = 9.0;
      final headCy = y + headR + 2;
      children.add(SceneShape(
        geometry: CircleGeometry(Point(cx, headCy), headR),
        fill: Fill(labelColor),
      ));
      children.add(SceneShape(
        geometry: _shouldersPath(cx, headCy + headR + 2, 22, 16),
        fill: Fill(labelColor),
      ));
      y += 48;
    }
    y += 8;
    children.add(SceneText(
      text: n.label,
      bounds: Rect.fromLTWH(rect.center.x - box.label.width / 2, y,
          box.label.width, box.label.height),
      style: labelStyle,
      color: labelColor,
    ));
    y += box.label.height;
    if (box.techn.height > 0) {
      y += 5;
      children.add(SceneText(
        text: '[${n.technology}]',
        bounds: Rect.fromLTWH(rect.center.x - box.techn.width / 2, y,
            box.techn.width, box.techn.height),
        style: technStyle,
        color: labelColor,
      ));
      y += box.techn.height;
    }
    if (box.desc.height > 0) {
      y += 20;
      children.add(SceneText(
        text: n.description,
        bounds: Rect.fromLTWH(rect.center.x - box.desc.width / 2, y,
            box.desc.width, box.desc.height),
        style: descStyle,
        color: labelColor,
      ));
    }
    elementNodes.add(
        SceneGroup(id: id, semanticLabel: n.label, children: children));
  });

  var nodes = <SceneNode>[
    ...clusterNodes,
    ...edgeNodes,
    ...labelNodes,
    ...elementNodes,
  ];
  var bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 100, 60);
  final title = diagram.title;
  if (title != null && title.isNotEmpty) {
    final style = TextStyleSpec(
        fontFamily: theme.fontFamily,
        fontSize: theme.fontSize * 1.15,
        fontWeight: 700);
    final size = measurer.measure(title, style);
    final node = SceneText(
      text: title,
      bounds: Rect.fromLTWH(bounds.center.x - size.width / 2,
          bounds.top - size.height - 12, size.width, size.height),
      style: style,
      color: theme.titleColor,
    );
    nodes = [...nodes, node];
    bounds = bounds.union(node.bounds);
  }
  final dx = pad - bounds.left;
  final dy = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
  );
}

// Cylinder (database) outline — top ellipse + body, mirroring the upstream
// `system_db` path (cap height ~10px).
PathGeometry _cylinderPath(Rect r) {
  const cap = 10.0;
  final l = r.left, t = r.top, b = r.bottom;
  final cx = r.center.x;
  return PathGeometry([
    MoveTo(Point(l, t + cap)),
    CubicTo(Point(l, t), Point(cx, t), Point(cx, t)),
    CubicTo(Point(cx, t), Point(r.right, t), Point(r.right, t + cap)),
    LineTo(Point(r.right, b - cap)),
    CubicTo(Point(r.right, b), Point(cx, b), Point(cx, b)),
    CubicTo(Point(cx, b), Point(l, b), Point(l, b - cap)),
    LineTo(Point(l, t + cap)),
    // Top ellipse front edge.
    MoveTo(Point(l, t + cap)),
    CubicTo(Point(l, t + 2 * cap), Point(cx, t + 2 * cap), Point(cx, t + 2 * cap)),
    CubicTo(Point(cx, t + 2 * cap), Point(r.right, t + 2 * cap),
        Point(r.right, t + cap)),
  ]);
}

// Queue (horizontal pill) outline mirroring the upstream `*_queue` path.
PathGeometry _queuePath(Rect r) {
  final l = r.left, t = r.top, b = r.bottom, right = r.right;
  final cy = r.center.y;
  return PathGeometry([
    MoveTo(Point(l, t)),
    LineTo(Point(right, t)),
    CubicTo(Point(right + 5, t), Point(right + 5, cy), Point(right + 5, cy)),
    CubicTo(Point(right + 5, b), Point(right, b), Point(right, b)),
    LineTo(Point(l, b)),
    CubicTo(Point(l - 5, b), Point(l - 5, cy), Point(l - 5, cy)),
    CubicTo(Point(l - 5, t), Point(l, t), Point(l, t)),
    // Right-side seam line.
    MoveTo(Point(right, t)),
    CubicTo(Point(right - 5, t), Point(right - 5, cy), Point(right - 5, cy)),
    CubicTo(Point(right - 5, b), Point(right, b), Point(right, b)),
  ]);
}

// Simple trapezoid "shoulders" under the avatar head.
PolygonGeometry _shouldersPath(double cx, double topY, double w, double h) {
  return PolygonGeometry([
    Point(cx - w / 2, topY + h),
    Point(cx - w / 2 + 3, topY),
    Point(cx + w / 2 - 3, topY),
    Point(cx + w / 2, topY + h),
  ]);
}

Point _intersectRect(Rect rect, Point outside) {
  final c = rect.center;
  final dx = outside.x - c.x;
  final dy = outside.y - c.y;
  if (dx == 0 && dy == 0) return c;
  final w = rect.width / 2;
  final h = rect.height / 2;
  double sx, sy;
  if (dy.abs() * w > dx.abs() * h) {
    sy = dy < 0 ? -h : h;
    sx = dx * sy / dy;
  } else {
    sx = dx < 0 ? -w : w;
    sy = dy * sx / dx;
  }
  return Point(c.x + sx, c.y + sy);
}

Point _dir(Point from, Point to) {
  final d = to - from;
  final len = math.sqrt(d.x * d.x + d.y * d.y);
  return len == 0 ? const Point(0, 1) : Point(d.x / len, d.y / len);
}
