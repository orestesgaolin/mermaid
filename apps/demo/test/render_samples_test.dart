/// Renders every demo sample offscreen to PNG (build/sample_renders/) and
/// doubles as an end-to-end render smoke test for the full pipeline:
/// source -> parse -> layout (FlutterTextMeasurer) -> ScenePainter -> image.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

const _samples = <String, String>{
  'basic_flow': '''
graph TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Ship it]
    B -->|No| D[Debug]
    D --> B
    C --> E[Celebrate]
''',
  'shapes': '''
graph TD
    A[Rectangle] --> B(Rounded)
    B --> C([Stadium])
    C --> D[[Subroutine]]
    D --> E[(Database)]
    E --> F((Circle))
    F --> G>Asymmetric]
    G --> H{Diamond}
    H --> I{{Hexagon}}
''',
  'edges': '''
graph LR
    A --> B
    B --- C
    C -.-> D
    D ==> E
    E <--> F
    F x--x G
    G o--o H
    A -->|labeled| H
''',
  'subgraphs': '''
graph LR
    subgraph Pipeline
        subgraph Stage One
            a1[Fetch] --> a2[Validate]
        end
        subgraph Stage Two
            b1[Transform] --> b2[Store]
        end
        a2 --> b1
    end
    Start([Start]) --> a1
    b2 --> Done([Done])
''',
  'styled': '''
graph TD
    A[Normal] --> B[Styled]:::hot
    B --> C[Inline styled]
    style C fill:#bfb,stroke:#393,stroke-width:3px
    classDef hot fill:#fbb,stroke:#933,stroke-width:2px
''',
  'cicd': '''
graph LR
    dev[Developer] --> push[Git push]
    push --> trigger{CI triggered?}
    trigger -->|yes| lint[Lint]
    trigger -->|no| idle([Idle])
    lint --> unit[Unit tests]
    unit --> build[Build artifacts]
    build --> integ[Integration tests]
    integ --> ok{All green?}
    ok -->|no| notify[Notify author]
    notify --> dev
    ok -->|yes| stage[Deploy to staging]
    stage --> smoke[Smoke tests]
    smoke --> approve{Manual approval}
    approve -->|approved| prod[Deploy to production]
    approve -->|rejected| notify
    prod --> monitor[(Metrics & alerts)]
''',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Use the real font so PNGs match the live app (tests default to Ahem).
    const path = '/System/Library/Fonts/Supplemental/Trebuchet MS.ttf';
    if (File(path).existsSync()) {
      final bytes = File(path).readAsBytesSync();
      final loader = FontLoader('trebuchet ms')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  });

  final outDir = Directory('build/sample_renders');

  for (final entry in _samples.entries) {
    test('renders ${entry.key}', () async {
      final mermaid = core.Mermaid(measurer: const FlutterTextMeasurer());
      final scene = mermaid.render(entry.value);
      expect(scene.size.width, greaterThan(0));
      expect(scene.size.height, greaterThan(0));

      const scale = 2.0;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..scale(scale);
      ScenePainter(scene).paint(
        canvas,
        ui.Size(scene.size.width, scene.size.height),
      );
      final image = await recorder.endRecording().toImage(
            (scene.size.width * scale).ceil(),
            (scene.size.height * scale).ceil(),
          );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      outDir.createSync(recursive: true);
      File('${outDir.path}/${entry.key}.png')
          .writeAsBytesSync(png!.buffer.asUint8List());
    });
  }
}
