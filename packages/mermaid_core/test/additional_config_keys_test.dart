import 'dart:convert';
import 'package:mermaid_core/mermaid_core.dart';
import 'package:test/test.dart';
import 'support/fixtures.dart';

const _renderer = Mermaid(measurer: ApproximateTextMeasurer());
void main() {
  final configs =
      jsonDecode(
            r'''{"architecture": {"iconSize": 100, "padding": 60, "fontSize": 22, "nodeSeparation": 120}, "block": {"padding": 40}, "cynefin": {"width": 720, "height": 450, "padding": 60, "showDomainDescriptions": false, "boundaryAmplitude": 0, "seed": 123}, "eventmodeling": {"padding": 50, "rowHeight": 200}, "ishikawa": {"diagramPadding": 60}, "journey": {"diagramMarginX": 80, "diagramMarginY": 30, "leftMargin": 220, "maxLabelWidth": 12, "boxTextMargin": 15, "width": 220, "height": 90, "taskMargin": 90, "taskFontSize": 22, "taskFontFamily": "serif", "actorColours": ["#ff0000"], "sectionFills": ["#abcdef"], "sectionColours": ["#123456"], "titleColor": "#123456", "titleFontFamily": "serif", "titleFontSize": 40}, "kanban": {"padding": 30, "sectionWidth": 300, "ticketBaseUrl": "https://example.com/ticket/#TICKET#"}, "mindmap": {"padding": 30, "maxNodeWidth": 30, "layoutAlgorithm": "tidy-tree"}, "packet": {"rowHeight": 80, "bitWidth": 20, "bitsPerRow": 8, "showBits": false, "paddingX": 30, "paddingY": 30}, "radar": {"width": 700, "height": 500, "marginTop": 80, "marginRight": 80, "marginBottom": 80, "marginLeft": 80, "axisScaleFactor": 0.7, "axisLabelFactor": 1.4, "curveTension": 0}, "requirement": {"rect_fill": "#ff0000", "text_color": "#0000ff", "rect_border_size": "4px", "rect_border_color": "#00ff00", "rect_min_width": 400, "rect_min_height": 300, "fontSize": 22, "rect_padding": 30, "line_height": 30}, "railroad": {"compactMode": true, "padding": 40, "verticalSeparation": 60, "horizontalSeparation": 50, "arcRadius": 20, "fontSize": 22, "fontFamily": "serif", "terminalFill": "#abcdef", "terminalStroke": "#123456", "terminalTextColor": "#112233", "nonTerminalFill": "#abcdef", "nonTerminalStroke": "#123456", "nonTerminalTextColor": "#112233", "lineColor": "#123456", "strokeWidth": 4, "markerFill": "#123456", "specialFill": "#abcdef", "specialStroke": "#123456", "ruleNameColor": "#123456", "showMarkers": false, "markerRadius": 12}, "timeline": {"leftMargin": 100, "padding": 40, "disableMulticolor": true}, "treemap": {"padding": 30, "diagramPadding": 30, "showValues": false, "nodeWidth": 160, "nodeHeight": 80, "valueFormat": ".2f"}, "venn": {"width": 700, "height": 500, "padding": 40, "useDebugLayout": true}, "wardley": {"width": 800, "height": 720, "padding": 70, "nodeRadius": 12, "nodeLabelOffset": 25, "axisFontSize": 22, "labelFontSize": 20, "showGrid": true}}''',
          )
          as Map<String, dynamic>;
  for (final diagram in configs.entries) {
    for (final entry in (diagram.value as Map<String, dynamic>).entries) {
      test(
        '${diagram.key}.${entry.key} affects rendering through init and frontmatter',
        () {
          final body = readFixture('configuration/${diagram.key}.mmd');
          final key = diagram.key == 'wardley' ? 'wardley-beta' : diagram.key;
          final init =
              '%%{init: ${jsonEncode({
                key: {entry.key: entry.value},
              })}}%%\n$body';
          final frontmatter =
              '---\nconfig:\n  $key:\n    ${entry.key}: ${jsonEncode(entry.value)}\n---\n$body';
          final baseline = renderSceneToSvg(_renderer.render(body));
          final configured = renderSceneToSvg(_renderer.render(init));
          expect(
            configured,
            isNot(baseline),
            reason:
                'The individual setting must change scene geometry or paint.',
          );
          expect(renderSceneToSvg(_renderer.render(frontmatter)), configured);
        },
      );
    }
  }
}
