/// Git graph: model, parser and layout — one file.
///
/// Reference: upstream gitGraphAst / gitGraphRenderer. Supports the core
/// operations (commit, branch, checkout/switch, merge, cherry-pick) with
/// commit id/type/tag attributes, and the default left-to-right (`LR`) and
/// top-to-bottom (`TB`) orientations. Commits are positioned by insertion
/// order (temporal layout); each branch gets its own lane.
library;

import '../../color.dart';
import '../../detect.dart';
import '../../geometry.dart';
import '../../ir/scene.dart';
import '../../ir/scene_utils.dart';
import '../../parse_error.dart';
import '../../text/text_measurer.dart';
import '../../text/text_style.dart';
import '../../theme/theme.dart';

enum GitCommitType { normal, reverse, highlight }

enum GitDirection { leftRight, topBottom }

class GitCommit {
  GitCommit({
    required this.id,
    required this.seq,
    required this.branch,
    required this.parents,
    this.type = GitCommitType.normal,
    this.tag,
    this.isMerge = false,
    this.isCherryPick = false,
  });

  final String id;

  /// Position slot in temporal (insertion) order.
  final int seq;
  final String branch;

  /// Parent commit ids (0 for the first commit, 1 normally, 2 for a merge).
  final List<String> parents;
  final GitCommitType type;
  final String? tag;
  final bool isMerge;
  final bool isCherryPick;
}

class GitGraph {
  GitGraph({
    required this.commits,
    required this.branchOrder,
    required this.direction,
  });

  final List<GitCommit> commits;

  /// Branch names in declaration order (main first).
  final List<String> branchOrder;
  final GitDirection direction;
}

GitGraph parseGitGraph(String source) {
  final text = stripMetadata(source);
  final lines = text.split('\n');
  var direction = GitDirection.leftRight;

  final commits = <GitCommit>[];
  final commitById = <String, GitCommit>{};
  final branchOrder = <String>['main'];
  final branchHead = <String, String?>{'main': null};
  var current = 'main';
  var seq = 0;
  var autoId = 0;
  var seenHeader = false;

  String unquote(String s) {
    final t = s.trim();
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }

  // Parses `key: value` / `key:value` attributes (id/type/tag) from the
  // remainder of a commit/merge line.
  ({String? id, GitCommitType type, String? tag}) parseAttrs(String rest) {
    String? id;
    var type = GitCommitType.normal;
    String? tag;
    final re = RegExp(r'(id|type|tag)\s*:\s*("[^"]*"|\S+)');
    for (final m in re.allMatches(rest)) {
      final key = m.group(1)!;
      final value = unquote(m.group(2)!);
      switch (key) {
        case 'id':
          id = value;
        case 'tag':
          tag = value;
        case 'type':
          type = switch (value.toUpperCase()) {
            'REVERSE' => GitCommitType.reverse,
            'HIGHLIGHT' => GitCommitType.highlight,
            _ => GitCommitType.normal,
          };
      }
    }
    return (id: id, type: type, tag: tag);
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final comment = line.indexOf('%%');
    if (comment >= 0) line = line.substring(0, comment);
    line = line.trim();
    if (line.isEmpty) continue;

    if (!seenHeader) {
      final m = RegExp(r'^gitGraph\b\s*(TB|BT|LR|RL)?\s*:?\s*(.*)$',
              caseSensitive: false)
          .firstMatch(line);
      if (m == null) {
        throw MermaidParseException('expected "gitGraph" header', line: i + 1);
      }
      final dir = m.group(1)?.toUpperCase();
      if (dir == 'TB' || dir == 'BT') direction = GitDirection.topBottom;
      seenHeader = true;
      final trailing = m.group(2)!.trim();
      if (trailing.isEmpty) continue;
      line = trailing; // `gitGraph: commit` on one line.
    }

    final word = RegExp(r'^(\w[\w-]*)').firstMatch(line)?.group(1) ?? '';
    final rest = line.substring(word.length).trim();

    switch (word) {
      case 'commit':
        final attrs = parseAttrs(rest);
        final id = attrs.id ?? '${current}_${autoId++}';
        final parents = [if (branchHead[current] != null) branchHead[current]!];
        final c = GitCommit(
          id: id,
          seq: seq++,
          branch: current,
          parents: parents,
          type: attrs.type,
          tag: attrs.tag,
        );
        commits.add(c);
        commitById[id] = c;
        branchHead[current] = id;

      case 'branch':
        final name = unquote(rest.split(RegExp(r'\s+order\s*:')).first);
        if (name.isEmpty) {
          throw MermaidParseException('branch requires a name', line: i + 1);
        }
        if (!branchOrder.contains(name)) branchOrder.add(name);
        branchHead[name] = branchHead[current];
        current = name;

      case 'checkout':
      case 'switch':
        final name = unquote(rest);
        if (!branchHead.containsKey(name)) {
          throw MermaidParseException('unknown branch "$name"', line: i + 1);
        }
        current = name;

      case 'merge':
        final parts = rest.split(RegExp(r'\s+'));
        final from = unquote(parts.first);
        if (!branchHead.containsKey(from)) {
          throw MermaidParseException(
              'cannot merge unknown branch "$from"', line: i + 1);
        }
        final attrs = parseAttrs(rest.substring(parts.first.length));
        final id = attrs.id ?? 'merge_${autoId++}';
        final parents = <String>[
          if (branchHead[current] != null) branchHead[current]!,
          if (branchHead[from] != null) branchHead[from]!,
        ];
        final c = GitCommit(
          id: id,
          seq: seq++,
          branch: current,
          parents: parents,
          type: attrs.type,
          tag: attrs.tag,
          isMerge: true,
        );
        commits.add(c);
        commitById[id] = c;
        branchHead[current] = id;

      case 'cherry-pick':
        final attrs = parseAttrs(rest);
        final parents = [if (branchHead[current] != null) branchHead[current]!];
        final c = GitCommit(
          id: 'cherry_${autoId++}',
          seq: seq++,
          branch: current,
          parents: parents,
          tag: attrs.id, // show the picked id as a tag
          isCherryPick: true,
        );
        commits.add(c);
        commitById[c.id] = c;
        branchHead[current] = c.id;

      default:
        // Tolerate unknown lines (accTitle/accDescr/directives already gone).
        break;
    }
  }

  if (!seenHeader) {
    throw const MermaidParseException('empty gitGraph source');
  }
  return GitGraph(
    commits: commits,
    branchOrder: branchOrder,
    direction: direction,
  );
}

/// Default branch palette (git0..git7), sampled from upstream's default-theme
/// gitGraph render: git0 blue, git1 yellow, then saturated hue rotations.
const _branchColors = <Color>[
  Color(0xff0000ec),
  Color(0xffdede00),
  Color(0xff00d6b3),
  Color(0xff0076ec),
  Color(0xff00ecec),
  Color(0xff00ec76),
  Color(0xffec00ec),
  Color(0xffec0000),
];

/// Perceived luminance, for readable label text on a branch fill.
double _luminance(Color c) =>
    (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) / 255;

RenderScene layoutGitGraph(
  GitGraph graph, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const commitR = 10.0;
  const commitGap = 50.0; // along the time axis
  const laneGap = 50.0; // between branch lanes
  const labelStyleSize = 12.0;
  final lr = graph.direction == GitDirection.leftRight;
  final labelStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: labelStyleSize);
  final branchLabelStyle = labelStyle.copyWith(fontWeight: 700);

  final laneOf = <String, int>{
    for (var i = 0; i < graph.branchOrder.length; i++) graph.branchOrder[i]: i,
  };
  Color branchColor(String b) =>
      _branchColors[(laneOf[b] ?? 0) % _branchColors.length];

  // Position helpers: time axis grows along x (LR) or y (TB); lanes along
  // the other axis.
  const timeBase = 70.0; // leave room for branch labels
  const laneBase = 40.0;
  Point posOf(GitCommit c) {
    final t = timeBase + c.seq * commitGap;
    final l = laneBase + (laneOf[c.branch] ?? 0) * laneGap;
    return lr ? Point(t, l) : Point(l, t);
  }

  final centers = <String, Point>{
    for (final c in graph.commits) c.id: posOf(c),
  };

  final nodes = <SceneNode>[];

  // Edges (parent → commit) under the nodes.
  for (final c in graph.commits) {
    final to = centers[c.id]!;
    for (final pid in c.parents) {
      final from = centers[pid];
      if (from == null) continue;
      final color = branchColor(c.isMerge && pid == c.parents.last
          ? graph.commits.firstWhere((x) => x.id == pid).branch
          : c.branch);
      nodes.add(_edge(from, to, color, lr));
    }
  }

  // Commit nodes.
  for (final c in graph.commits) {
    final center = centers[c.id]!;
    final color = branchColor(c.branch);
    final children = <SceneNode>[];
    switch (c.type) {
      case GitCommitType.highlight:
        children.add(SceneShape(
          geometry: RectGeometry(
              Rect.fromCenter(center, commitR * 2.4, commitR * 2.4)),
          fill: Fill(color),
          stroke: Stroke(color: theme.textColor, width: 2),
        ));
      case GitCommitType.reverse:
        children.add(SceneShape(
          geometry: CircleGeometry(center, commitR),
          fill: Fill(color),
          stroke: Stroke(color: theme.textColor, width: 1.5),
        ));
        // Cross marker.
        final d = commitR * 0.6;
        children.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(center.x - d, center.y - d)),
            LineTo(Point(center.x + d, center.y + d)),
            MoveTo(Point(center.x + d, center.y - d)),
            LineTo(Point(center.x - d, center.y + d)),
          ]),
          stroke: Stroke(color: theme.textColor, width: 1.5),
        ));
      case GitCommitType.normal:
        children.add(SceneShape(
          geometry: CircleGeometry(center, commitR),
          fill: Fill(c.isCherryPick ? const Color(0xffffffff) : color),
          stroke: Stroke(color: color, width: c.isCherryPick ? 2 : 1.5),
        ));
        if (c.isMerge) {
          children.add(SceneShape(
            geometry: CircleGeometry(center, commitR * 0.45),
            fill: Fill(theme.background),
          ));
        }
    }

    // Commit id label below (LR) / right (TB).
    final showId = !c.id.startsWith('${c.branch}_') &&
        !c.id.startsWith('merge_') &&
        !c.id.startsWith('cherry_');
    if (showId) {
      final size = measurer.measure(c.id, labelStyle, maxWidth: 200);
      final lblCenter = lr
          ? Point(center.x, center.y + commitR + 4 + size.height / 2)
          : Point(center.x + commitR + 4 + size.width / 2, center.y);
      children.add(SceneText(
        text: c.id,
        bounds: Rect.fromCenter(lblCenter, size.width, size.height),
        style: labelStyle,
        color: theme.textColor,
      ));
    }

    // Tag flag.
    if (c.tag != null && c.tag!.isNotEmpty) {
      final size = measurer.measure(c.tag!, labelStyle, maxWidth: 200);
      final tagCenter = lr
          ? Point(center.x, center.y - commitR - 6 - size.height / 2)
          : Point(center.x - commitR - 6 - size.width / 2, center.y);
      children.add(SceneShape(
        geometry: RectGeometry(
            Rect.fromCenter(
                tagCenter, size.width + 12, size.height + 6),
            rx: 3,
            ry: 3),
        fill: const Fill(Color(0xfffff5ad)),
        stroke: const Stroke(color: Color(0xffaaaa33)),
      ));
      children.add(SceneText(
        text: c.tag!,
        bounds: Rect.fromCenter(tagCenter, size.width, size.height),
        style: labelStyle,
        color: const Color(0xff333322),
      ));
    }

    nodes.add(SceneGroup(id: 'commit_${c.id}', children: children));
  }

  // Branch labels at the start of each lane.
  for (final b in graph.branchOrder) {
    // Only label branches that actually have commits or are main.
    final hasCommit = graph.commits.any((c) => c.branch == b);
    if (!hasCommit && b != 'main') continue;
    final color = branchColor(b);
    final size = measurer.measure(b, branchLabelStyle, maxWidth: 200);
    final lane = laneBase + (laneOf[b] ?? 0) * laneGap;
    final center =
        lr ? Point(8 + size.width / 2 + 6, lane) : Point(lane, 8 + size.height);
    nodes.add(SceneShape(
      geometry: RectGeometry(
          Rect.fromCenter(center, size.width + 14, size.height + 8),
          rx: 4,
          ry: 4),
      fill: Fill(color),
    ));
    nodes.add(SceneText(
      text: b,
      bounds: Rect.fromCenter(center, size.width, size.height),
      style: branchLabelStyle,
      color: _luminance(color) < 0.6
          ? const Color(0xffffffff)
          : const Color(0xff000000),
    ));
  }

  final bounds = sceneBounds(nodes) ?? const Rect.fromLTWH(0, 0, 120, 80);
  const pad = 16.0;
  final dx = pad - bounds.left;
  final dy = pad - bounds.top;
  return RenderScene(
    size: Size(bounds.width + 2 * pad, bounds.height + 2 * pad),
    background: theme.background,
    nodes: [for (final n in nodes) translateSceneNode(n, dx, dy)],
  );
}

/// An L-shaped/orthogonal edge from parent to child, turning at the corner so
/// branch points and merges read as right-angle git connectors.
SceneShape _edge(Point from, Point to, Color color, bool lr) {
  final commands = <PathCommand>[MoveTo(from)];
  if (lr) {
    if ((from.y - to.y).abs() < 0.5) {
      commands.add(LineTo(to));
    } else {
      // Travel along the parent lane, then curve into the child lane.
      final cornerX = to.x - 25;
      commands
        ..add(LineTo(Point(cornerX, from.y)))
        ..add(CubicTo(Point(cornerX + 12, from.y),
            Point(to.x, to.y - (to.y - from.y) * 0.4), to));
    }
  } else {
    if ((from.x - to.x).abs() < 0.5) {
      commands.add(LineTo(to));
    } else {
      final cornerY = to.y - 25;
      commands
        ..add(LineTo(Point(from.x, cornerY)))
        ..add(CubicTo(Point(from.x, cornerY + 12),
            Point(to.x - (to.x - from.x) * 0.4, to.y), to));
    }
  }
  return SceneShape(
    geometry: PathGeometry(commands),
    stroke: Stroke(color: color, width: 2.5),
  );
}
