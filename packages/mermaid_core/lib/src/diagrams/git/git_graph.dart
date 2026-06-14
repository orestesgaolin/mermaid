/// Git graph: model, parser and layout — one file.
///
/// Reference: upstream gitGraphAst / gitGraphRenderer. Supports the core
/// operations (commit, branch, checkout/switch, merge, cherry-pick) with
/// commit id/type/tag attributes, and the `LR`, `TB` and `BT` orientations.
/// Commit positions are parent-relative (each commit sits one step past its
/// closest parent); each branch gets its own lane. Default theme values are
/// inlined to match mermaid.js's default-theme gitGraph render.
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

enum GitCommitType { normal, reverse, highlight }

enum GitDirection { leftRight, topBottom, bottomTop }

class GitCommit {
  GitCommit({
    required this.id,
    required this.seq,
    required this.branch,
    required this.parents,
    this.type = GitCommitType.normal,
    List<String>? tags,
    this.customId = false,
    this.isMerge = false,
    this.isCherryPick = false,
  }) : tags = tags ?? const [];

  final String id;

  /// Position slot in temporal (insertion) order.
  final int seq;
  final String branch;

  /// Parent commit ids (0 for the first commit, 1 normally, 2 for a merge).
  final List<String> parents;
  final GitCommitType type;

  /// Tags attached to this commit; rendered as stacked flag labels.
  final List<String> tags;

  /// The first tag, or null when untagged. Convenience accessor kept for
  /// callers that expect a single tag.
  String? get tag => tags.isEmpty ? null : tags.first;

  /// True when the commit's id was supplied explicitly (`id:`); controls
  /// whether a merge commit shows its label (upstream `customId`).
  final bool customId;
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

  /// Branch names in declaration order (main first), adjusted for `order:`.
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
  final branchOrderValue = <String, int>{'main': 0};
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
  // remainder of a commit/merge line. `tag` may appear more than once.
  ({String? id, GitCommitType type, List<String> tags}) parseAttrs(String rest) {
    String? id;
    var type = GitCommitType.normal;
    final tags = <String>[];
    final re = RegExp(r'(id|type|tag)\s*:\s*("[^"]*"|\S+)');
    for (final m in re.allMatches(rest)) {
      final key = m.group(1)!;
      final value = unquote(m.group(2)!);
      switch (key) {
        case 'id':
          id = value;
        case 'tag':
          tags.add(value);
        case 'type':
          type = switch (value.toUpperCase()) {
            'REVERSE' => GitCommitType.reverse,
            'HIGHLIGHT' => GitCommitType.highlight,
            _ => GitCommitType.normal,
          };
      }
    }
    return (id: id, type: type, tags: tags);
  }

  int? parseOrder(String rest) {
    final m = RegExp(r'order\s*:\s*(\d+)').firstMatch(rest);
    return m == null ? null : int.tryParse(m.group(1)!);
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
      if (dir == 'TB') direction = GitDirection.topBottom;
      if (dir == 'BT') direction = GitDirection.bottomTop;
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
          tags: attrs.tags,
          customId: attrs.id != null,
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
        final order = parseOrder(rest);
        if (order != null) branchOrderValue[name] = order;
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
          tags: attrs.tags,
          customId: attrs.id != null,
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
          // show the picked id as a tag
          tags: [if (attrs.id != null) attrs.id!, ...attrs.tags],
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

  // Sort branches by their `order:` value when supplied (main stays 0 unless
  // overridden), preserving declaration order as the tie-breaker — mirrors
  // upstream `compareBranchesByOrder`.
  if (branchOrderValue.length > 1) {
    final declIndex = {
      for (var i = 0; i < branchOrder.length; i++) branchOrder[i]: i,
    };
    branchOrder.sort((a, b) {
      final oa = branchOrderValue[a];
      final ob = branchOrderValue[b];
      if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
      if (oa != null && ob == null) return oa.compareTo(declIndex[b]!);
      if (oa == null && ob != null) return declIndex[a]!.compareTo(ob);
      return declIndex[a]!.compareTo(declIndex[b]!);
    });
  }

  return GitGraph(
    commits: commits,
    branchOrder: branchOrder,
    direction: direction,
  );
}

RenderScene layoutGitGraph(
  GitGraph graph, {
  required TextMeasurer measurer,
  required MermaidTheme theme,
}) {
  const commitR = 10.0;
  const commitStep = 40.0; // COMMIT_STEP
  const layoutOffset = 10.0; // LAYOUT_OFFSET
  const defaultPos = 30.0; // TB/BT lane time-origin
  // LR lane gap: 50 + 40 (rotateCommitLabel defaults true). TB/BT lanes add
  // half the (rotated) commit-label width; we approximate with the same gap.
  const laneGap = 90.0;
  const commitLabelSize = 10.0;
  const tagLabelSize = 10.0;
  final lr = graph.direction == GitDirection.leftRight;
  final tb = graph.direction == GitDirection.topBottom ||
      graph.direction == GitDirection.bottomTop;
  final bt = graph.direction == GitDirection.bottomTop;

  final commitLabelStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: commitLabelSize);
  final tagLabelStyle =
      TextStyleSpec(fontFamily: theme.fontFamily, fontSize: tagLabelSize);
  final branchLabelStyle = TextStyleSpec(
      fontFamily: theme.fontFamily, fontSize: 12, fontWeight: 700);

  // gitGraph palette (git0..git7) and the matching highlight / branch-label
  // colors come from the theme; the default-theme values equal upstream
  // theme-default.js (git0=darken(primaryColor,25), …).
  final gitColors = theme.git;
  final gitInvColors = theme.gitInv;
  final gitBranchLabelColors = theme.gitBranchLabel;

  final laneOf = <String, int>{
    for (var i = 0; i < graph.branchOrder.length; i++) graph.branchOrder[i]: i,
  };
  Color branchColor(String b) =>
      gitColors[(laneOf[b] ?? 0) % gitColors.length];
  int branchIndex(String b) => (laneOf[b] ?? 0) % gitColors.length;

  // Lane spine coordinate (perpendicular to the time axis) for a branch.
  double laneCoord(String b) => (laneOf[b] ?? 0) * laneGap;

  final commitById = {for (final c in graph.commits) c.id: c};
  final branchOf = {for (final c in graph.commits) c.id: c.branch};

  // Parent-relative time positions: a commit sits one COMMIT_STEP past its
  // closest parent along the time axis. Commits are walked in seq order; the
  // running `pos` advances by COMMIT_STEP+LAYOUT_OFFSET each commit, and a
  // commit's time is max(running pos, closestParent + step) so side branches
  // can share a fork's slot. (Mirrors calculatePosition + the pos cursor.)
  final timeOf = <String, double>{};
  var pos = tb ? defaultPos : 0.0;
  var maxPos = 0.0;
  final ordered = [...graph.commits]..sort((a, b) => a.seq.compareTo(b.seq));
  for (final c in ordered) {
    double t;
    if (c.parents.isEmpty) {
      t = pos + layoutOffset;
    } else {
      var parentMax = double.negativeInfinity;
      for (final pid in c.parents) {
        final pt = timeOf[pid];
        if (pt != null && pt > parentMax) parentMax = pt;
      }
      final fromParent =
          parentMax.isFinite ? parentMax + commitStep : pos + layoutOffset;
      final cursor = pos + layoutOffset;
      t = math.max(fromParent, cursor);
    }
    timeOf[c.id] = t;
    if (t > maxPos) maxPos = t;
    pos = math.max(pos, t - layoutOffset) + commitStep + layoutOffset;
  }
  final timeSpanMax = maxPos + commitStep;

  // For BT the time axis is reversed (origin at the bottom).
  double timeToCoord(double t) => bt ? (timeSpanMax - t) : t;

  Point centerOf(GitCommit c) {
    final t = timeToCoord(timeOf[c.id]!);
    final lane = laneCoord(c.branch);
    // LR: commits sit 2px above the spine (upstream `branchY - 2`).
    return lr ? Point(t, lane - 2) : Point(lane, t);
  }

  final centers = {for (final c in graph.commits) c.id: centerOf(c)};

  final nodes = <SceneNode>[];

  // Branch lane lines: a dashed neutral line at strokeWidth=1 spanning the
  // whole diagram (0..maxPos along the time axis), colored lineColor — not the
  // branch color (upstream `.branch` style).
  for (final b in graph.branchOrder) {
    if (!graph.commits.any((c) => c.branch == b) && b != 'main') continue;
    final spine = laneCoord(b);
    final start = timeToCoord(tb ? defaultPos : 0);
    final end = timeToCoord(timeSpanMax);
    final lo = math.min(start, end);
    final hi = math.max(start, end);
    final p1 = lr ? Point(lo, spine - 2) : Point(spine, lo);
    final p2 = lr ? Point(hi, spine - 2) : Point(spine, hi);
    nodes.add(SceneShape(
      geometry: PathGeometry([MoveTo(p1), LineTo(p2)]),
      stroke: Stroke(color: theme.lineColor, width: 1, dash: const [2, 2]),
    ));
  }

  // Arrows: one for EVERY parent → child edge (including consecutive
  // same-branch commits). Stroke width 8, round caps, no fill, colored by the
  // destination branch (or source branch for merge second parents / upward
  // arrows). Bends are 20-radius quarter-circle arcs.
  for (final c in graph.commits) {
    final to = centers[c.id]!;
    for (var pi = 0; pi < c.parents.length; pi++) {
      final pid = c.parents[pi];
      final from = centers[pid];
      if (from == null) continue;
      final parent = commitById[pid];
      final isMergeSecond = c.isMerge && pi > 0;
      // color = destination branch, except for merge-of-second-parent and
      // "upward" arrows where the source branch's color is used.
      final color = _arrowColor(
        from: from,
        to: to,
        sourceBranch: branchOf[pid]!,
        destBranch: c.branch,
        isMergeSecond: isMergeSecond,
        lr: lr,
        branchColor: branchColor,
      );
      nodes.add(_arrow(
        from: from,
        to: to,
        color: color,
        lr: lr,
        bt: bt,
        isMergeSecond: isMergeSecond,
        sourceMatchesFirstParent: parent != null && pi == 0,
      ));
    }
  }

  // Commit bullets.
  for (final c in graph.commits) {
    final center = centers[c.id]!;
    final color = branchColor(c.branch);
    final idx = branchIndex(c.branch);
    final children = <SceneNode>[];
    switch (c.type) {
      case GitCommitType.highlight:
        // Outer rect 20×20 filled with gitInv{i}; inner rect 12×12 filled
        // with primaryColor.
        children.add(SceneShape(
          geometry: RectGeometry(Rect.fromCenter(center, 20, 20)),
          fill: Fill(gitInvColors[idx]),
          stroke: Stroke(color: gitInvColors[idx], width: 1),
        ));
        children.add(SceneShape(
          geometry: RectGeometry(Rect.fromCenter(center, 12, 12)),
          fill: Fill(theme.primaryColor),
          stroke: Stroke(color: theme.primaryColor, width: 1),
        ));
      case GitCommitType.reverse:
        children.add(SceneShape(
          geometry: CircleGeometry(center, commitR),
          fill: Fill(color),
          stroke: Stroke(color: color, width: 1),
        ));
        // Cross marker: arm 5, stroke-width 3, primaryColor.
        const arm = 5.0;
        children.add(SceneShape(
          geometry: PathGeometry([
            MoveTo(Point(center.x - arm, center.y - arm)),
            LineTo(Point(center.x + arm, center.y + arm)),
            MoveTo(Point(center.x - arm, center.y + arm)),
            LineTo(Point(center.x + arm, center.y - arm)),
          ]),
          stroke: Stroke(color: theme.primaryColor, width: 3),
        ));
      case GitCommitType.normal:
        if (c.isCherryPick) {
          // Cherry glyph: r10 circle + two small white circles (r2.75 at
          // x±3, y+2) + two white stems up to (x, y−5).
          children.add(SceneShape(
            geometry: CircleGeometry(center, commitR),
            fill: Fill(color),
            stroke: Stroke(color: color, width: 1),
          ));
          for (final dx in const [-3.0, 3.0]) {
            children.add(SceneShape(
              geometry:
                  CircleGeometry(Point(center.x + dx, center.y + 2), 2.75),
              fill: const Fill(Color(0xffffffff)),
            ));
            children.add(SceneShape(
              geometry: PathGeometry([
                MoveTo(Point(center.x + dx, center.y + 1)),
                LineTo(Point(center.x, center.y - 5)),
              ]),
              stroke: const Stroke(color: Color(0xffffffff), width: 1),
            ));
          }
        } else {
          children.add(SceneShape(
            geometry: CircleGeometry(center, commitR),
            fill: Fill(color),
            stroke: Stroke(color: color, width: 1),
          ));
          if (c.isMerge) {
            // Inner circle r6 filled with primaryColor.
            children.add(SceneShape(
              geometry: CircleGeometry(center, 6),
              fill: Fill(theme.primaryColor),
              stroke: Stroke(color: theme.primaryColor, width: 1),
            ));
          }
        }
    }

    // Commit id label. Shown for every commit except cherry-picks and
    // non-custom-id merges, when showCommitLabel (default true). Font 10px,
    // commitLabelColor on a 50%-opacity commitLabelBackground rect (upstream
    // `.commit-label-bkg { opacity: 0.5 }`). Rotated −45° for LR
    // (rotateCommitLabel defaults true).
    final showLabel =
        !c.isCherryPick && (c.customId || !c.isMerge);
    if (showLabel) {
      final size = measurer.measure(c.id, commitLabelStyle, maxWidth: 200);
      final lblCenter = lr
          ? Point(center.x, center.y + commitR + 9 + size.height / 2)
          : Point(center.x - commitR - 8 - size.width / 2, center.y);
      const py = 2.0;
      children.add(SceneShape(
        geometry: RectGeometry(Rect.fromCenter(
            lblCenter, size.width + 2 * py, size.height + 2 * py)),
        fill: Fill(theme.commitLabelBackground.withOpacity(0.5)),
      ));
      children.add(SceneText(
        text: c.id,
        bounds: Rect.fromCenter(lblCenter, size.width, size.height),
        style: commitLabelStyle,
        color: theme.commitLabelColor,
        rotation: lr ? -45 : 0,
      ));
    }

    // Tags: a stack of flag labels offset by 20px each, placed above (LR) /
    // left (TB) of the commit. Flag = 6-point polygon + r1.5 hole circle.
    if (c.tags.isNotEmpty) {
      var tagOffset = 0.0;
      for (final tag in c.tags.reversed) {
        final size = measurer.measure(tag, tagLabelStyle, maxWidth: 200);
        final w = size.width;
        final h = size.height;
        const px = 4.0, py = 2.0;
        if (lr) {
          // Flag body center sits above the commit; the notch points down-left
          // toward the spine.
          final cy = center.y - 19.2 - tagOffset;
          final cx = center.x;
          final notchX = cx - w / 2 - px - 6; // pole side
          final h2 = h / 2;
          children.add(SceneShape(
            geometry: PolygonGeometry([
              Point(notchX, cy + py),
              Point(notchX, cy - py),
              Point(cx - w / 2 - px, cy - h2 - py),
              Point(cx + w / 2 + px, cy - h2 - py),
              Point(cx + w / 2 + px, cy + h2 + py),
              Point(cx - w / 2 - px, cy + h2 + py),
            ]),
            fill: Fill(theme.tagLabelBackground),
            stroke: Stroke(color: theme.tagLabelBorder, width: 1),
          ));
          children.add(SceneShape(
            geometry: CircleGeometry(Point(notchX + px / 2, cy), 1.5),
            fill: Fill(theme.textColor),
          ));
          children.add(SceneText(
            text: tag,
            bounds: Rect.fromCenter(Point(cx, cy), w, h),
            style: tagLabelStyle,
            color: theme.tagLabelColor,
          ));
        } else {
          final cx = center.x - commitR - 10 - tagOffset;
          final cy = center.y;
          final w2 = w / 2 + px;
          final h2 = h / 2 + py;
          children.add(SceneShape(
            geometry: PolygonGeometry([
              Point(cx + w2 + 6, cy - py),
              Point(cx + w2 + 6, cy + py),
              Point(cx + w2, cy + h2),
              Point(cx - w2, cy + h2),
              Point(cx - w2, cy - h2),
              Point(cx + w2, cy - h2),
            ]),
            fill: Fill(theme.tagLabelBackground),
            stroke: Stroke(color: theme.tagLabelBorder, width: 1),
          ));
          children.add(SceneShape(
            geometry: CircleGeometry(Point(cx + w2 + 5, cy), 1.5),
            fill: Fill(theme.textColor),
          ));
          children.add(SceneText(
            text: tag,
            bounds: Rect.fromCenter(Point(cx, cy), w, h),
            style: tagLabelStyle,
            color: theme.tagLabelColor,
          ));
        }
        tagOffset += 20;
      }
    }

    nodes.add(SceneGroup(id: 'commit_${c.id}', children: children));
  }

  // Branch labels: chip filled with the branch (label{i}=git{i}) color, text
  // gitBranchLabel{i} (white for branch 0/3, black otherwise), placed to the
  // left of the spine origin (LR) / above the lane (TB).
  for (final b in graph.branchOrder) {
    final hasCommit = graph.commits.any((c) => c.branch == b);
    if (!hasCommit && b != 'main') continue;
    final idx = branchIndex(b);
    final color = gitColors[idx];
    final size = measurer.measure(b, branchLabelStyle, maxWidth: 200);
    final spine = laneCoord(b);
    final Point center;
    if (lr) {
      // Left of the spine origin (x=0). bbox.width + ~14 to the left.
      center = Point(-(size.width / 2 + 11), spine - 2);
    } else {
      center = Point(spine, timeToCoord(tb ? 0 : defaultPos) - 4);
    }
    nodes.add(SceneShape(
      geometry: RectGeometry(
          Rect.fromCenter(center, size.width + 14, size.height + 4),
          rx: 4,
          ry: 4),
      fill: Fill(color),
    ));
    nodes.add(SceneText(
      text: b,
      bounds: Rect.fromCenter(center, size.width, size.height),
      style: branchLabelStyle,
      color: gitBranchLabelColors[idx],
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

/// Chooses the arrow color following upstream `drawArrow`: destination branch
/// color, but the source branch color for merge-of-second-parent arrows and
/// for arrows that travel "backward" along the time axis (child before parent).
Color _arrowColor({
  required Point from,
  required Point to,
  required String sourceBranch,
  required String destBranch,
  required bool isMergeSecond,
  required bool lr,
  required Color Function(String) branchColor,
}) {
  if (isMergeSecond) return branchColor(sourceBranch);
  // Upward / leftward arrow → source branch color.
  final backward = lr ? from.y > to.y : from.x > to.x;
  return branchColor(backward ? sourceBranch : destBranch);
}

/// A git connector arrow from parent (`from`) to child (`to`). Straight when
/// the two share a lane; otherwise a single 20-radius quarter-circle bend, with
/// the elbow shaped so branch-points fan out and merges fold in — mirroring
/// upstream `drawArrow`'s default (non-rerouted) path. Stroke width 8, round.
SceneShape _arrow({
  required Point from,
  required Point to,
  required Color color,
  required bool lr,
  required bool bt,
  required bool isMergeSecond,
  required bool sourceMatchesFirstParent,
}) {
  const radius = 20.0;
  final p1 = from;
  final p2 = to;
  // Each path is: line to the arc start, a quarter-circle arc bending around a
  // corner, then a line to the destination. Picks which leg runs along the
  // time axis vs the lane axis exactly as upstream does per direction/merge.
  final List<PathCommand> commands;
  if (lr) {
    if ((p1.y - p2.y).abs() < 0.5) {
      commands = [MoveTo(p1), LineTo(p2)];
    } else if (p1.y < p2.y) {
      if (isMergeSecond) {
        // Travel along source lane, arc down into destination lane.
        final arcStart = Point(p2.x - radius, p1.y);
        final corner = Point(p2.x, p1.y);
        final arcEnd = Point(p2.x, p1.y + radius);
        commands = [
          MoveTo(p1),
          LineTo(arcStart),
          ..._arc(arcStart, corner, arcEnd),
          LineTo(p2),
        ];
      } else {
        // Branch point: drop within source column, arc right into dest lane.
        final arcStart = Point(p1.x, p2.y - radius);
        final corner = Point(p1.x, p2.y);
        final arcEnd = Point(p1.x + radius, p2.y);
        commands = [
          MoveTo(p1),
          LineTo(arcStart),
          ..._arc(arcStart, corner, arcEnd),
          LineTo(p2),
        ];
      }
    } else {
      // Source below destination (upward arrow / merge fold-in).
      if (isMergeSecond) {
        final arcStart = Point(p2.x - radius, p1.y);
        final corner = Point(p2.x, p1.y);
        final arcEnd = Point(p2.x, p1.y - radius);
        commands = [
          MoveTo(p1),
          LineTo(arcStart),
          ..._arc(arcStart, corner, arcEnd),
          LineTo(p2),
        ];
      } else {
        final arcStart = Point(p1.x, p2.y + radius);
        final corner = Point(p1.x, p2.y);
        final arcEnd = Point(p1.x + radius, p2.y);
        commands = [
          MoveTo(p1),
          LineTo(arcStart),
          ..._arc(arcStart, corner, arcEnd),
          LineTo(p2),
        ];
      }
    }
  } else {
    // TB / BT: time axis is vertical, lanes are horizontal.
    if ((p1.x - p2.x).abs() < 0.5) {
      commands = [MoveTo(p1), LineTo(p2)];
    } else if (isMergeSecond) {
      // Travel along source lane (vertical), arc into destination column.
      final dirY = bt ? -radius : radius;
      final arcStart = Point(p1.x, p2.y - dirY);
      final corner = Point(p1.x, p2.y);
      final arcEnd = Point(p1.x + (p1.x < p2.x ? radius : -radius), p2.y);
      commands = [
        MoveTo(p1),
        LineTo(arcStart),
        ..._arc(arcStart, corner, arcEnd),
        LineTo(p2),
      ];
    } else {
      // Branch point: travel along the lane to the dest column, arc down.
      final dirY = bt ? -radius : radius;
      final arcStart = Point(p2.x - (p1.x < p2.x ? radius : -radius), p1.y);
      final corner = Point(p2.x, p1.y);
      final arcEnd = Point(p2.x, p1.y + dirY);
      commands = [
        MoveTo(p1),
        LineTo(arcStart),
        ..._arc(arcStart, corner, arcEnd),
        LineTo(p2),
      ];
    }
  }
  return SceneShape(
    geometry: PathGeometry(commands),
    stroke: Stroke(color: color, width: 8),
  );
}

/// A 90° rounded corner from [start] to [end] bending around [corner],
/// approximated with a cubic Bézier (the IR has no arc primitive). Control
/// points use the circle constant 0.5523 so the curve closely tracks a true
/// quarter circle of the implied radius.
List<PathCommand> _arc(Point start, Point corner, Point end) {
  const k = 0.5522847498;
  final c1 = Point(
    start.x + (corner.x - start.x) * k,
    start.y + (corner.y - start.y) * k,
  );
  final c2 = Point(
    end.x + (corner.x - end.x) * k,
    end.y + (corner.y - end.y) * k,
  );
  return [CubicTo(c1, c2, end)];
}
