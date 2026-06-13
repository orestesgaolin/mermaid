/// Top-level facade: source text in, render scene out.
library;

import 'detect.dart';
import 'diagrams/architecture/architecture.dart';
import 'diagrams/block/block.dart';
import 'diagrams/c4/c4.dart';
import 'diagrams/kanban/kanban.dart';
import 'diagrams/radar/radar.dart';
import 'diagrams/treemap/treemap.dart';
import 'diagrams/class_diagram/class_layout.dart';
import 'diagrams/class_diagram/class_parser.dart';
import 'diagrams/er/er_layout.dart';
import 'diagrams/er/er_parser.dart';
import 'diagrams/flowchart/flow_layout.dart';
import 'diagrams/flowchart/flow_parser.dart';
import 'diagrams/gantt/gantt_layout.dart';
import 'diagrams/git/git_graph.dart';
import 'diagrams/journey/journey.dart';
import 'diagrams/mindmap/mindmap.dart';
import 'diagrams/gantt/gantt_parser.dart';
import 'diagrams/pie/pie_layout.dart';
import 'diagrams/quadrant/quadrant.dart';
import 'diagrams/packet/packet.dart';
import 'diagrams/sankey/sankey.dart';
import 'diagrams/requirement/requirement.dart';
import 'diagrams/pie/pie_parser.dart';
import 'diagrams/sequence/sequence_layout.dart';
import 'diagrams/sequence/sequence_parser.dart';
import 'diagrams/state/state_layout.dart';
import 'diagrams/timeline/timeline.dart';
import 'diagrams/xychart/xychart.dart';
import 'directives.dart';
import 'diagrams/state/state_parser.dart';
import 'ir/scene.dart';
import 'parse_error.dart';
import 'render/rough.dart';
import 'text/text_measurer.dart';
import 'theme/theme.dart';

class Mermaid {
  const Mermaid({
    required this.measurer,
    this.theme = MermaidTheme.defaultTheme,
  });

  final TextMeasurer measurer;
  final MermaidTheme theme;

  /// Parses [source], lays it out, and returns the scene.
  ///
  /// Throws [MermaidParseException] on syntax errors and
  /// [UnsupportedError] for not-yet-ported diagram types.
  RenderScene render(String source) {
    final scene = _layout(source);
    // `look: 'handDrawn'` re-renders the scene in a sketchy style.
    final look = resolveLook(source);
    if (look.isHandDrawn) {
      return roughenScene(scene, seed: look.handDrawnSeed);
    }
    return scene;
  }

  RenderScene _layout(String source) {
    // %%{init}%% directives and frontmatter config.theme adjust the theme
    // per diagram, like upstream.
    final theme = resolveTheme(source, this.theme);
    switch (detectDiagramType(source)) {
      case DiagramType.flowchart:
        return layoutFlowchart(parseFlowchart(source),
            measurer: measurer, theme: theme);
      case DiagramType.sequence:
        return layoutSequence(parseSequence(source),
            measurer: measurer, theme: theme);
      case DiagramType.classDiagram:
        return layoutClassDiagram(parseClassDiagram(source),
            measurer: measurer, theme: theme);
      case DiagramType.stateDiagram:
        return layoutStateDiagram(parseStateDiagram(source),
            measurer: measurer, theme: theme);
      case DiagramType.er:
        return layoutErDiagram(parseErDiagram(source),
            measurer: measurer, theme: theme);
      case DiagramType.pie:
        return layoutPieChart(parsePieChart(source),
            measurer: measurer, theme: theme);
      case DiagramType.gantt:
        return layoutGanttChart(parseGanttChart(source),
            measurer: measurer, theme: theme);
      case DiagramType.quadrant:
        return layoutQuadrantChart(parseQuadrantChart(source),
            measurer: measurer, theme: theme);
      case DiagramType.journey:
        return layoutJourney(parseJourney(source),
            measurer: measurer, theme: theme);
      case DiagramType.timeline:
        return layoutTimeline(parseTimeline(source),
            measurer: measurer, theme: theme);
      case DiagramType.xychart:
        return layoutXyChart(parseXyChart(source),
            measurer: measurer, theme: theme);
      case DiagramType.mindmap:
        return layoutMindmap(parseMindmap(source),
            measurer: measurer, theme: theme);
      case DiagramType.requirement:
        return layoutRequirementDiagram(parseRequirementDiagram(source),
            measurer: measurer, theme: theme);
      case DiagramType.c4:
        return layoutC4Diagram(parseC4Diagram(source),
            measurer: measurer, theme: theme);
      case DiagramType.gitGraph:
        return layoutGitGraph(parseGitGraph(source),
            measurer: measurer, theme: theme);
      case DiagramType.sankey:
        return layoutSankey(parseSankey(source),
            measurer: measurer, theme: theme);
      case DiagramType.packet:
        return layoutPacket(parsePacket(source),
            measurer: measurer, theme: theme);
      case DiagramType.block:
        return layoutBlock(parseBlock(source),
            measurer: measurer, theme: theme);
      case DiagramType.radar:
        return layoutRadar(parseRadar(source),
            measurer: measurer, theme: theme);
      case DiagramType.treemap:
        return layoutTreemap(parseTreemap(source),
            measurer: measurer, theme: theme);
      case DiagramType.kanban:
        return layoutKanban(parseKanban(source),
            measurer: measurer, theme: theme);
      case DiagramType.architecture:
        return layoutArchitecture(parseArchitecture(source),
            measurer: measurer, theme: theme);
      case DiagramType.unknown:
        throw UnsupportedError(
          'Unrecognized or not-yet-supported diagram type. Currently '
          'supported: flowchart, sequence, class, state, er, pie, gantt, '
          'quadrantChart, journey, timeline, xychart, mindmap, '
          'requirementDiagram, C4, gitGraph, sankey, packet, block, radar, '
          'treemap, kanban, architecture.',
        );
    }
  }
}
