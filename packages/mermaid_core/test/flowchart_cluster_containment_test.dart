/// Cluster geometry of flowcharts whose subgraphs share nodes and have many
/// edges between them (issue #82).
///
/// Each node must lie inside the box of the subgraph that owns it, and only
/// that box; sibling boxes must not intersect. Ownership follows mermaid.js
/// (FlowDB.addSubGraph/makeUniq): the first subgraph to close with a node
/// listed owns it. The expected owners below were read from the mermaid.js
/// 11.17.2 render of each source.
library;

import 'package:mermaid_core/src/diagrams/flowchart/flow_layout.dart';
import 'package:mermaid_core/src/diagrams/flowchart/flow_parser.dart';
import 'package:mermaid_core/src/geometry.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/ir/scene_utils.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

RenderScene render(String source) => layoutFlowchart(
  parseFlowchart(source),
  measurer: const ApproximateTextMeasurer(),
  theme: MermaidTheme.defaultTheme,
);

/// Cluster boxes keyed by subgraph title.
Map<String, Rect> clusterBoxes(RenderScene scene) {
  final boxes = <String, Rect>{};
  void walk(Iterable<SceneNode> nodes) {
    for (final n in nodes) {
      if (n is! SceneGroup) continue;
      if (n.role == SceneGroupRole.cluster) {
        boxes[n.semanticLabel!] = n.children
            .whereType<SceneShape>()
            .map((s) => s.geometry)
            .whereType<RectGeometry>()
            .first
            .rect;
      }
      walk(n.children);
    }
  }

  walk(scene.nodes);
  return boxes;
}

bool encloses(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.right <= outer.right &&
    inner.top >= outer.top &&
    inner.bottom <= outer.bottom;

bool intersects(Rect a, Rect b) =>
    a.left < b.right &&
    b.left < a.right &&
    a.top < b.bottom &&
    b.top < a.bottom;

/// Checks that every node in [owners] lies inside its owner's box and in no
/// other box, and that no two cluster boxes intersect.
void expectClusters(RenderScene scene, Map<String, List<String>> owners) {
  final boxes = clusterBoxes(scene);
  expect(boxes.keys, unorderedEquals(owners.keys));
  final nodes = scene.nodeBounds;
  owners.forEach((title, ids) {
    for (final id in ids) {
      final containing = [
        for (final e in boxes.entries)
          if (encloses(e.value, nodes[id]!)) e.key,
      ];
      expect(containing, [title], reason: 'clusters containing node $id');
    }
  });
  final titles = boxes.keys.toList();
  for (var i = 0; i < titles.length; i++) {
    for (var j = i + 1; j < titles.length; j++) {
      expect(
        intersects(boxes[titles[i]]!, boxes[titles[j]]!),
        isFalse,
        reason: '"${titles[i]}" and "${titles[j]}" overlap',
      );
    }
  }
}

const issue82 = '''
flowchart TD
    classDef generator fill:#4b5320,stroke:#333,stroke-width:2px,color:#fff
    classDef machine fill:#3b5998,stroke:#333,stroke-width:2px,color:#fff
    classDef assembly fill:#8b0000,stroke:#333,stroke-width:2px,color:#fff
    classDef storage fill:#d2691e,stroke:#333,stroke-width:2px,color:#fff
    W[(Water Network)]:::storage
    subgraph Cluster 1: Clay Production
        CG1[Cobblestone Gen]:::generator -->|Cobblestone| M1[Macerator 1]:::machine
        M1 -->|Gravel| M2[Macerator 2]:::machine
        M2 -->|Sand| M3[Macerator 3]:::machine
        M3 -->|Dust| CR1[Chemical Reactor]:::machine
        W --> CR1
    end
    subgraph Cluster 2: Nether Quartz Production
        CG2[Cobblestone Gen]:::generator -->|Cobblestone| M4[Macerator 4]:::machine
        M4 -->|Gravel| M5[Macerator 5]:::machine
        M5 -->|Sand| EF1[Electric Furnace]:::machine
        EF1 -->|Glass| EL[Electrolyzer]:::machine
    end
    subgraph Cluster 3: Pulsating Dust Production
        FE[Fluid Extractor]:::machine -->|Liquid Ender| CR2[Chemical Reactor]:::machine
        EL -->|Nether Quartz| CR2
        CR2 -->|Ender Clathrates| EF2[Electric Furnace]:::machine
    end
    subgraph Cluster 4: Final Assembly & Loop
        CR1 -->|Clay| IH[Impulse Hopper]:::assembly
        EF2 -->|Pulsating Dust| IH
        IH -->|Balanced 1:1| AS[Alloy Smelter]:::assembly
        AS -->|Polymer Clay| SC[Simulation Chamber]:::assembly
        SC -->|Ender Pearls| FE
        SC -->|Pristine Matter| Loot[To Loot Fabricator / Storage]:::storage
    end
''';

// The reporter's second source: IH is first listed in Cluster 1 and CR2 in
// Cluster 2, so those clusters own them.
const issue82Variant = '''
flowchart TD
    subgraph Cluster 1: Clay
        CG1[Cobblestone Generator] -->|Cobblestone| M1[Macerator 1]
        M1 -->|Gravel| M2[Macerator 2]
        M2 -->|Sand| M3[Macerator 3]
        M3 -->|Dust| CR1[Chemical Reactor 1]
        Water[Water Source] -->|Water| CR1
        CR1 -->|Clay| IH[Impulse Hopper]
    end
    subgraph Cluster 2: Nether Quartz
        CG2[Cobblestone Generator] -->|Cobblestone| M4[Macerator 4]
        M4 -->|Gravel| M5[Macerator 5]
        M5 -->|Sand| EF1[Electric Furnace 1]
        EF1 -->|Glass| EL[Electrolyzer]
        EL -->|Nether Quartz| CR2[Chemical Reactor 2]
    end
    subgraph Cluster 3: Pulsating Dust
        FE[Fluid Extractor] -->|Liquid Ender| CR2
        CR2 -->|Clathrates| EF2[Electric Furnace 2]
        EF2 -->|Pulsating Dust| IH
    end
    subgraph Cluster 4: Polymer Clay Loop
        IH -->|1 Clay + 1 Dust| AS[Alloy Smelter]
        AS -->|Polymer Clay| SC[Simulation Chamber]
        SC -.->|Ender Pearls| FE
    end
''';

void main() {
  test('issue 82: nodes stay in the cluster that first lists them', () {
    expectClusters(render(issue82), {
      'Cluster 1: Clay Production': ['W', 'CG1', 'M1', 'M2', 'M3', 'CR1'],
      'Cluster 2: Nether Quartz Production': ['CG2', 'M4', 'M5', 'EF1', 'EL'],
      'Cluster 3: Pulsating Dust Production': ['FE', 'CR2', 'EF2'],
      'Cluster 4: Final Assembly & Loop': ['IH', 'AS', 'SC', 'Loot'],
    });
  });

  test('issue 82 variant: shared nodes stay with their first cluster', () {
    expectClusters(render(issue82Variant), {
      'Cluster 1: Clay': ['CG1', 'M1', 'M2', 'M3', 'CR1', 'Water', 'IH'],
      'Cluster 2: Nether Quartz': ['CG2', 'M4', 'M5', 'EF1', 'EL', 'CR2'],
      'Cluster 3: Pulsating Dust': ['FE', 'EF2'],
      'Cluster 4: Polymer Clay Loop': ['AS', 'SC'],
    });
  });

  test('an earlier sibling keeps a node a later nested subgraph uses', () {
    // x is listed in A, then in C (nested in B). A closes first, so A owns
    // x; C owns only y.
    final scene = render('''
flowchart TD
  subgraph A
    x
  end
  subgraph B
    subgraph C
      x --> y
    end
  end
''');
    final boxes = clusterBoxes(scene);
    final x = scene.nodeBounds['x']!;
    final y = scene.nodeBounds['y']!;
    expect(encloses(boxes['A']!, x), isTrue);
    expect(encloses(boxes['B']!, x), isFalse);
    expect(encloses(boxes['C']!, y), isTrue);
    expect(encloses(boxes['B']!, boxes['C']!), isTrue);
    expect(intersects(boxes['A']!, boxes['B']!), isFalse);
  });
}
