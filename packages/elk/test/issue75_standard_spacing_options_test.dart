import 'package:elk/elk.dart';
import 'package:test/test.dart';

void main() {
  test('standard elkjs spacing names drive public layout behavior', () {
    final options = ElkLayoutOptions.fromElkJson({
      'elk.spacing.labelNode': 7,
      'elk.spacing.labelPortHorizontal': 3,
      'elk.spacing.portsSurrounding': '[top=11,bottom=13]',
      'elk.spacing.nodeSelfLoop': 30,
    });

    expect(options.spacingNodeLabel, 7);
    expect(options.spacingPortLabel, 3);
    expect(options.spacingPortsSurroundingTop, 11);
    expect(options.spacingPortsSurroundingBottom, 13);
    expect(options.resolvedNodeSelfLoop, 30);

    final defaultResult = const ElkLayered().layout(
      const ElkGraph(
        children: [ElkNode(id: 'n', width: 40, height: 40)],
        edges: [
          ElkEdge(id: 'loop', sources: ['n'], targets: ['n']),
        ],
      ),
    );
    final spacedResult = const ElkLayered().layout(
      ElkGraph(
        layoutOptions: options,
        children: const [ElkNode(id: 'n', width: 40, height: 40)],
        edges: const [
          ElkEdge(id: 'loop', sources: ['n'], targets: ['n']),
        ],
      ),
    );

    expect(spacedResult.height, greaterThan(defaultResult.height));
  });

  test('legacy spacing aliases retain their existing values', () {
    final options = ElkLayoutOptions.fromElkJson({
      'elk.spacing.nodeLabel': 8,
      'elk.spacing.portLabel': 4,
      'elk.spacing.portsSurrounding.top': 12,
      'elk.spacing.portsSurrounding.bottom': 14,
      'elk.spacing.edgeNode': 16,
    });

    expect(options.spacingNodeLabel, 8);
    expect(options.spacingPortLabel, 4);
    expect(options.spacingPortsSurroundingTop, 12);
    expect(options.spacingPortsSurroundingBottom, 14);
    expect(options.resolvedNodeSelfLoop, 16);
  });
}
