import 'package:mermaid_core/src/vendor/dagre/dart_dagre.dart';
import 'package:mermaid_core/src/vendor/dagre/src/model/props.dart';

class GraphLabel extends Props {
  RankDir rankDir = RankDir.ttb;
  GraphAlign? align;
  double nodeSep = 50;
  double edgeSep = 20;
  double rankSep = 50;
  double marginX = 0;
  double marginY = 0;
  Acyclicer acyclicer = Acyclicer.none;
  Ranker ranker = Ranker.networkSimplex;
  double? width;
  double? height;

  GraphLabel({
    this.nodeSep = 50,
    this.edgeSep = 20,
    this.rankSep = 50,
    this.rankDir = RankDir.ttb,
  });

  @override
  GraphLabel copy() {
    GraphLabel label = GraphLabel(nodeSep: nodeSep, edgeSep: edgeSep, rankSep: rankSep, rankDir: rankDir);
    label.putAll(getAll());
    label.align = align;
    label.marginX = marginX;
    label.marginY = marginY;
    label.acyclicer = acyclicer;
    label.ranker = ranker;
    label.width = width;
    label.height = height;
    return label;
  }
}
