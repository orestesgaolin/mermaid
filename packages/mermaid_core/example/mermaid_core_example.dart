// Renders a flowchart to SVG with the pure-Dart core.
//
// Run: dart run example/mermaid_core_example.dart
import 'package:mermaid_core/mermaid_core.dart';

void main() {
  const source = '''
graph TD
  A[Start] --> B{Is it working?}
  B -->|Yes| C[Ship it]
  B -->|No| D[Debug]
  D --> B
''';

  const mermaid = Mermaid(measurer: ApproximateTextMeasurer());
  final scene = mermaid.render(source);

  // The scene is backend-agnostic; here we render it to an SVG string.
  print(renderSceneToSvg(scene));

  // You can also inspect the detected type and scene size.
  // (Printed to stderr so stdout stays valid SVG.)
}
