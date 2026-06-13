/// Tests for the packet diagram.
library;

import 'package:mermaid_core/src/detect.dart';
import 'package:mermaid_core/src/diagrams/packet/packet.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/parse_error.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

List<SceneNode> flatten(List<SceneNode> nodes) => [
      for (final n in nodes) ...[
        n,
        if (n is SceneGroup) ...flatten(n.children),
      ],
    ];

void main() {
  test('detects packet / packet-beta', () {
    expect(detectDiagramType('packet\n0: "x"'), DiagramType.packet);
    expect(detectDiagramType('packet-beta\n0: "x"'), DiagramType.packet);
  });

  group('parse', () {
    test('ranges, single bits and +count continuation', () {
      final p = parsePacket('''
packet
0-15: "A"
16: "B"
+8: "C"
''');
      expect(p.fields[0].start, 0);
      expect(p.fields[0].end, 15);
      expect(p.fields[1].start, 16);
      expect(p.fields[1].end, 16);
      // +8 continues from bit 17 for 8 bits → 17..24.
      expect(p.fields[2].start, 17);
      expect(p.fields[2].end, 24);
      expect(p.fields[2].bits, 8);
    });

    test('in-body title statement', () {
      final p = parsePacket('packet\ntitle My Packet\n0: "x"');
      expect(p.title, 'My Packet');
    });

    test('rejects malformed field', () {
      expect(() => parsePacket('packet\nnonsense'),
          throwsA(isA<MermaidParseException>()));
    });
  });

  group('layout', () {
    test('splits a wide field across 32-bit rows', () {
      // 0..63 spans two rows → two block groups for that field.
      final scene = layoutPacket(
        parsePacket('packet\n0-63: "Wide"'),
        measurer: measurer,
        theme: theme,
      );
      final blocks = scene.nodes
          .whereType<SceneGroup>()
          .where((g) => g.id!.startsWith('packet_'))
          .toList();
      expect(blocks.length, 2);
      // Both segments are labelled.
      final texts =
          flatten(scene.nodes).whereType<SceneText>().map((t) => t.text);
      expect(texts.where((t) => t == 'Wide').length, 2);
      // Bit markers 0, 31, 32, 63 present.
      expect(texts.toSet().containsAll({'0', '31', '32', '63'}), isTrue);
    });
  });
}
