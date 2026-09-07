import 'support/scene.dart';
import 'package:mermaid_core/src/diagrams/block/block.dart';
import 'package:mermaid_core/src/diagrams/packet/packet.dart';
import 'package:mermaid_core/src/diagrams/requirement/requirement.dart';
import 'package:mermaid_core/src/color.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

const measurer = ApproximateTextMeasurer();
const theme = MermaidTheme.defaultTheme;

void main() {
  test('block padding config changes node geometry', () {
    const source = 'block-beta\n  A["A"]';
    final diagram = parseBlock(source);
    final normal = layoutBlock(diagram, measurer: measurer, theme: theme);
    final padded = layoutBlock(
      diagram,
      measurer: measurer,
      theme: theme,
      config: const BlockConfig(padding: 40),
    );
    expect(padded.size.width, greaterThan(normal.size.width));
    expect(
      BlockConfig.fromSource('''
%%{init: {"block": {"padding": 40}}}%%
block-beta
A
''').padding,
      40,
    );
  });

  test('requirement config changes minimum box size, text, and fill', () {
    const source = 'requirementDiagram\nrequirement R {\nid: 1\n}';
    final scene = layoutRequirementDiagram(
      parseRequirementDiagram(source),
      measurer: measurer,
      theme: theme,
      config: const RequirementConfig(
        rectMinWidth: 300,
        rectMinHeight: 250,
        rectFill: Color(0xffff0000),
        textColor: Color(0xff0000ff),
      ),
    );
    final group = flattenScene(
      scene.nodes,
    ).whereType<SceneGroup>().singleWhere((node) => node.id == 'R');
    final rect =
        group.children.whereType<SceneShape>().first.geometry as RectGeometry;
    expect(rect.rect.width, greaterThanOrEqualTo(300));
    expect(rect.rect.height, greaterThanOrEqualTo(250));
    expect(
      group.children.whereType<SceneShape>().first.fill?.color,
      const Color(0xffff0000),
    );
    expect(
      group.children.whereType<SceneText>().any(
        (text) => text.color == const Color(0xff0000ff),
      ),
      isTrue,
    );
  });

  test('packet config changes row and bit geometry and hides bit labels', () {
    final packet = parsePacket('packet\n0-7: "Header"\n8-15: "Body"');
    final normal = layoutPacket(packet, measurer: measurer, theme: theme);
    final compact = layoutPacket(
      packet,
      measurer: measurer,
      theme: theme,
      config: const PacketConfig(
        rowHeight: 48,
        bitWidth: 20,
        bitsPerRow: 8,
        paddingX: 2,
        paddingY: 0,
        showBits: false,
      ),
    );
    expect(compact.size.height, greaterThan(normal.size.height));
    expect(compact.size.width, lessThan(normal.size.width));
    expect(
      flattenScene(
        compact.nodes,
      ).whereType<SceneText>().map((text) => text.text),
      isNot(contains('0')),
    );
    final values = PacketConfig.fromSource('''
%%{init: {"packet": {"bitsPerRow": 8, "showBits": false}}}%%
packet
0: "x"
''');
    expect(values.bitsPerRow, 8);
    expect(values.showBits, isFalse);
  });
}
