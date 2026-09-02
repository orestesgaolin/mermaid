import 'package:mermaid_core/src/diagrams/gantt/gantt_layout.dart';
import 'package:mermaid_core/src/diagrams/gantt/gantt_parser.dart';
import 'package:mermaid_core/src/ir/scene.dart';
import 'package:mermaid_core/src/render/svg_renderer.dart';
import 'package:mermaid_core/src/text/approximate_text_measurer.dart';
import 'package:mermaid_core/src/theme/theme.dart';
import 'package:test/test.dart';

void main() {
  test('grid paints behind opaque task bars', () {
    final scene = layoutGanttChart(
      parseGanttChart('''
gantt
    dateFormat YYYY-MM-DD
    title Release plan
    todayMarker off
    excludes weekends
    section Design
    Wireframes      : done, des1, 2024-03-01, 4d
    Visual design   : active, des2, after des1, 5d
    section Build
    API             : crit, api1, 2024-03-04, 7d
    Frontend        : fe1, after des2, 6d
'''),
      measurer: const ApproximateTextMeasurer(),
      theme: MermaidTheme.defaultTheme,
    );

    final svg = renderSceneToSvg(scene);
    final excludedDays = svg.indexOf('fill="#eeeeee"');
    final lastGrid = svg.lastIndexOf('stroke="#d3d3d3"');
    final firstTask = svg.indexOf('<g id="des1"');
    expect(excludedDays, greaterThanOrEqualTo(0));
    expect(lastGrid, greaterThan(excludedDays));
    expect(lastGrid, greaterThanOrEqualTo(0));
    expect(firstTask, greaterThan(lastGrid));

    final task = scene.nodes.whereType<SceneGroup>().firstWhere(
      (group) => group.id == 'des1',
    );
    final taskBar = task.children.whereType<SceneShape>().firstWhere(
      (shape) => shape.geometry is RectGeometry,
    );
    expect(taskBar.fill?.color.alpha, 255);
  });
}
