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
  'v11_shapes': '''
flowchart LR
    in@{ shape: start, label: " " } --> read@{ shape: datastore, label: "Read config" }
    read --> check@{ shape: decision, label: "Valid?" }
    check -->|yes| run@{ shape: subprocess, label: "Run job" }
    check -->|no| fix@{ shape: manual, label: "Fix by hand" }
    fix --> read
    run --> report@{ shape: doc, label: "Report" }
    report --> out@{ shape: stop, label: " " }
''',
  'self_loops': '''
graph TD
    boot[Boot] --> poll[Poll queue]
    poll -->|empty| poll
    poll -->|job| work[Process job<br/>with retries]
    work -->|retry| work
    work -->|done| ack[Acknowledge]
    work -->|fatal| dead[(Dead letter)]
    ack --> poll
''',
  'mixed_directions': '''
graph TB
    req[Request] --> auth
    subgraph mw[Middleware chain]
        direction LR
        auth[Auth] --> rate[Rate limit] --> log[Logging]
    end
    log --> app[App handler]
    app --> resp[Response]
''',
  'microservices': '''
graph LR
    web[Web client] --> gw[API Gateway]
    mobile[Mobile app] --> gw
    subgraph services[Services]
        direction TB
        gw2[Router] --> users[Users svc]
        gw2 --> orders[Orders svc]
        gw2 --> billing[Billing svc]
    end
    gw ==> gw2
    users --> udb[(Users DB)]
    orders --> odb[(Orders DB)]
    orders -.->|events| bus{{Message bus}}
    billing -.->|events| bus
    bus -.-> mail[Email worker]
    bus -.-> analytics[Analytics sink]
    linkStyle default stroke:#666
''',
  'sequence': '''
sequenceDiagram
    autonumber
    actor U as User
    participant W as Web App
    participant S as Auth Service
    U->>+W: Login request
    W->>+S: Validate credentials
    Note right of S: Check password hash
    alt valid
        S-->>W: Token
        W-->>U: Welcome!
    else invalid
        S-->>-W: 401
        W-->>-U: Try again
    end
    loop every 15 min
        W->>S: Refresh token
        S--)W: New token
    end
''',
  'class_diagram': '''
classDiagram
    direction TB
    class Animal {
        <<abstract>>
        +String name
        +int age
        +isMammal() bool
        +mate()*
    }
    class Duck {
        +String beakColor
        +swim()
        +quack()
    }
    class Fish {
        -int sizeInFeet
        -canEat() bool
    }
    Animal <|-- Duck
    Animal <|-- Fish
    Duck "1" --> "*" Egg : lays
    note for Duck "can fly<br/>and swim"
''',
  'state_machine': '''
stateDiagram-v2
    [*] --> Idle
    Idle --> Connecting : connect
    state check <<choice>>
    Connecting --> check
    check --> Connected : ok
    check --> Backoff : failed
    Backoff --> Connecting : retry
    state Connected {
        [*] --> Receiving
        Receiving --> Processing : message
        Processing --> Receiving : done
    }
    Connected --> Connected : heartbeat
    Connected --> Closing : close
    Closing --> [*]
    note right of Backoff : exponential<br/>backoff
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
