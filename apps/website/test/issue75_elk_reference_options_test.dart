import 'package:elk/elk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website/elk_demos.dart';
import 'package:website/elk_reference.dart';

void main() {
  test('reference JSON uses the same effective standard spacing options', () {
    const graph = ElkGraph(
      layoutOptions: ElkLayoutOptions(
        padding: ElkPadding(top: 1, left: 2, bottom: 3, right: 4),
        spacingNodeLabel: 7,
        spacingPortLabel: 3,
        spacingPortsSurroundingTop: 11,
        spacingPortsSurroundingBottom: 13,
        spacingNodeSelfLoop: 17,
      ),
      children: [
        ElkNode(
          id: 'compound',
          labels: [ElkLabel(text: 'Group', width: 40, height: 10)],
          children: [ElkNode(id: 'child', width: 20, height: 20)],
        ),
      ],
    );

    final json = elkGraphToJson(graph);
    final options = (json['layoutOptions'] as Map).cast<String, dynamic>();
    expect(options['elk.padding'], '[top=1.0,left=2.0,bottom=3.0,right=4.0]');
    expect(options['elk.spacing.labelNode'], 7);
    expect(options['elk.spacing.labelPortHorizontal'], 3);
    expect(options['elk.spacing.labelPortVertical'], 3);
    expect(options['elk.spacing.portsSurrounding'], '[top=11.0,bottom=13.0]');
    expect(options['elk.spacing.nodeSelfLoop'], 17);
    expect(options, isNot(contains('elk.spacing.nodeLabel')));
    expect(options, isNot(contains('elk.spacing.portLabel')));
    expect(options, isNot(contains('elk.spacing.portsSurrounding.top')));

    final compound = ((json['children'] as List).single as Map)
        .cast<String, dynamic>();
    expect(
      (compound['layoutOptions'] as Map)['elk.nodeLabels.placement'],
      'INSIDE V_TOP H_CENTER',
    );

    final decoded = ElkGraph.fromJson(json);
    expect(decoded.layoutOptions.padding.top, 1);
    expect(decoded.layoutOptions.spacingNodeLabel, 7);
    expect(decoded.layoutOptions.spacingPortLabel, 3);
    expect(decoded.layoutOptions.spacingPortsSurroundingTop, 11);
    expect(decoded.layoutOptions.spacingPortsSurroundingBottom, 13);
    expect(decoded.layoutOptions.resolvedNodeSelfLoop, 17);
  });

  test(
    'broker example sends the same loop and port clearances to both engines',
    () {
      final example = buildElkExamples().singleWhere(
        (item) => item.title == 'Ports, loops, and a message broker',
      );
      final json = elkGraphToJson(example.graph);
      final options = (json['layoutOptions'] as Map).cast<String, dynamic>();

      expect(
        options['elk.padding'],
        '[top=12.0,left=12.0,bottom=12.0,right=12.0]',
      );
      expect(options['elk.spacing.edgeNode'], 20);
      expect(options['elk.spacing.nodeSelfLoop'], 20);
      expect(options['elk.spacing.portsSurrounding'], '[top=10.0,bottom=10.0]');

      final decoded = ElkGraph.fromJson(json).layoutOptions;
      expect(decoded.padding.top, 12);
      expect(decoded.resolvedEdgeNode, 20);
      expect(decoded.resolvedNodeSelfLoop, 20);
      expect(decoded.spacingPortsSurroundingTop, 10);
      expect(decoded.spacingPortsSurroundingBottom, 10);
    },
  );
}
