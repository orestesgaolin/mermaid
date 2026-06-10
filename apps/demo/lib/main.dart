import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
  // Lets tooling (screenshots, UI driving) attach in debug builds.
  // Text entry emulation must stay OFF or it hijacks the platform text
  // input connection and real keyboard typing stops working; automation
  // can enable it at runtime via the set_text_entry_emulation command.
  if (kDebugMode) {
    enableFlutterDriverExtension(enableTextEntryEmulation: false);
  }
  runApp(const MermaidDemoApp());
}

// ---------------------------------------------------------------------------
// Samples
// ---------------------------------------------------------------------------

class Sample {
  const Sample(this.name, this.source);

  final String name;
  final String source;
}

const _samples = <Sample>[
  Sample('Basic flow', '''
graph TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Ship it]
    B -->|No| D[Debug]
    D --> B
    C --> E[Celebrate]
'''),
  Sample('Shapes', '''
graph TD
    A[Rectangle] --> B(Rounded)
    B --> C([Stadium])
    C --> D[[Subroutine]]
    D --> E[(Database)]
    E --> F((Circle))
    F --> G>Asymmetric]
    G --> H{Diamond}
    H --> I{{Hexagon}}
    I --> J[/Parallelogram/]
    J --> K[\\Parallelogram alt\\]
    K --> L[/Trapezoid\\]
    L --> M[\\Trapezoid alt/]
    M --> N(((Double circle)))
'''),
  Sample('Edges', '''
graph LR
    A[A] --> B[B]
    B --- C[C]
    C -.-> D[D]
    D ==> E[E]
    E --o F[F]
    F --x G[G]
    G <--> H[H]
    A -- solid label --> E
    B -.->|dotted label| F
    C ==>|thick label| G
'''),
  Sample('Subgraphs', '''
graph LR
    subgraph Pipeline
        direction LR
        subgraph Stage One
            direction TB
            a1[Fetch] --> a2[Validate]
        end
        subgraph Stage Two
            direction TB
            b1[Transform] --> b2[Store]
        end
        a2 --> b1
    end
    Start([Start]) --> a1
    b2 --> Done([Done])
'''),
  Sample('Styled', '''
graph TD
    classDef hot fill:#ffcccc,stroke:#cc0000,stroke-width:2px,color:#660000
    classDef cool fill:#cce5ff,stroke:#0055aa,color:#003366
    A[Normal node] --> B[Hot node]:::hot
    A --> C[Cool node]:::cool
    B --> D{Decision}
    C --> D
    D -->|left| E[Result]
    style A fill:#ffffcc,stroke:#aaaa00,stroke-width:3px
    style E fill:#e6ffe6,stroke:#00aa00
'''),
  Sample('CI/CD pipeline', '''
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
'''),
  Sample('v11 shapes', '''
flowchart LR
    in@{ shape: start, label: " " } --> read@{ shape: datastore, label: "Read config" }
    read --> check@{ shape: decision, label: "Valid?" }
    check -->|yes| run@{ shape: subprocess, label: "Run job" }
    check -->|no| fix@{ shape: manual, label: "Fix by hand" }
    fix --> read
    run --> report@{ shape: doc, label: "Report" }
    report --> out@{ shape: stop, label: " " }
'''),
  Sample('Self-loops', '''
graph TD
    boot[Boot] --> poll[Poll queue]
    poll -->|empty| poll
    poll -->|job| work[Process job<br/>with retries]
    work -->|retry| work
    work -->|done| ack[Acknowledge]
    work -->|fatal| dead[(Dead letter)]
    ack --> poll
'''),
  Sample('Mixed directions', '''
graph TB
    req[Request] --> auth
    subgraph mw[Middleware chain]
        direction LR
        auth[Auth] --> rate[Rate limit] --> log[Logging]
    end
    log --> app[App handler]
    app --> resp[Response]
'''),
  Sample('Microservices', '''
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
'''),
  Sample('Sequence', '''
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
'''),
  Sample('Class diagram', '''
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
    class Zebra {
        +bool is_wild
        +run()
    }
    Animal <|-- Duck
    Animal <|-- Fish
    Animal <|-- Zebra
    Duck "1" --> "*" Egg : lays
    note for Duck "can fly<br/>and swim"
'''),
  Sample('State machine', '''
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
'''),
  Sample('ER diagram', '''
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    PRODUCT }|..|{ LINE_ITEM : "ordered in"
    CUSTOMER {
        string name PK "full name"
        string email UK
        int loyaltyPoints
    }
    ORDER {
        int orderNumber PK
        date placedAt
        string status FK
    }
'''),
  Sample('Gantt', '''
gantt
    dateFormat YYYY-MM-DD
    title Release plan
    section Design
    Wireframes      : done, des1, 2024-03-01, 4d
    Visual design   : active, des2, after des1, 5d
    section Build
    API             : crit, api1, 2024-03-04, 7d
    Frontend        : fe1, after des2, 6d
    Integration     : after api1 fe1, 3d
    section Launch
    Beta            : milestone, 2024-03-20, 1d
    Rollout         : after fe1, 4d
'''),
  Sample('Pie', '''
pie showData title Browser share
    "Chrome" : 64.7
    "Safari" : 18.1
    "Edge" : 5.4
    "Firefox" : 3.1
    "Other" : 8.7
'''),
  Sample('Quadrant', '''
quadrantChart
    title Reach and engagement of campaigns
    x-axis Low Reach --> High Reach
    y-axis Low Engagement --> High Engagement
    quadrant-1 We should expand
    quadrant-2 Need to promote
    quadrant-3 Re-evaluate
    quadrant-4 May be improved
    Campaign A: [0.3, 0.6]
    Campaign B: [0.45, 0.23]
    Campaign C: [0.57, 0.69]
    Campaign D: [0.78, 0.34]
    Campaign E: [0.40, 0.34]
'''),
  Sample('Journey', '''
journey
    title My working day
    section Go to work
      Make tea: 5: Me
      Go upstairs: 3: Me
      Do work: 1: Me, Cat
    section Go home
      Go downstairs: 5: Me
      Sit down: 5: Me
'''),
  Sample('Timeline', '''
timeline
    title History of Social Media
    section Web 1.0
    2002 : LinkedIn
    2004 : Facebook : Google
    section Web 2.0
    2005 : YouTube
    2006 : Twitter
'''),
];

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class MermaidDemoApp extends StatefulWidget {
  const MermaidDemoApp({super.key});

  @override
  State<MermaidDemoApp> createState() => _MermaidDemoAppState();
}

class _MermaidDemoAppState extends State<MermaidDemoApp> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mermaid Dart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF9370DB),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF81B1DB),
        brightness: Brightness.dark,
      ),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: EditorPage(
        dark: _dark,
        onToggleDark: () => setState(() => _dark = !_dark),
      ),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.dark, required this.onToggleDark});

  final bool dark;
  final VoidCallback onToggleDark;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController _controller;
  Timer? _debounce;
  int _sampleIndex = 0;
  String _renderedSource = _samples.first.source;
  bool _autoFit = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _samples.first.source);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSourceChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _renderedSource = text);
    });
  }

  void _selectSample(int index) {
    _debounce?.cancel();
    setState(() {
      _sampleIndex = index;
      _controller.text = _samples[index].source;
      _renderedSource = _samples[index].source;
    });
  }

  /// Per-session theme overrides from the style editor; reset by the
  /// light/dark toggle or the editor's reset button.
  core.MermaidTheme? _themeOverride;

  core.MermaidTheme get _baseTheme => widget.dark
      ? core.MermaidTheme.darkTheme
      : core.MermaidTheme.defaultTheme;

  core.MermaidTheme get _mermaidTheme => _themeOverride ?? _baseTheme;

  @override
  void didUpdateWidget(EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Light/dark switch resets style-editor overrides to the new base.
    if (oldWidget.dark != widget.dark) _themeOverride = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mermaid Dart'),
        actions: [
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Edit diagram styles',
              icon: Badge(
                isLabelVisible: _themeOverride != null,
                child: const Icon(Icons.palette_outlined),
              ),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
          IconButton(
            tooltip:
                widget.dark ? 'Switch to light theme' : 'Switch to dark theme',
            icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleDark,
          ),
          const SizedBox(width: 8),
        ],
      ),
      endDrawer: Drawer(
        width: 340,
        child: SafeArea(
          child: ThemeEditor(
            theme: _mermaidTheme,
            modified: _themeOverride != null,
            onChanged: (t) => setState(() => _themeOverride = t),
            onReset: () => setState(() => _themeOverride = null),
          ),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 420, child: _buildEditorPane(colors)),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _buildPreviewPane()),
        ],
      ),
    );
  }

  Widget _buildEditorPane(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _samples.length; i++)
                ChoiceChip(
                  label: Text(_samples[i].name),
                  selected: _sampleIndex == i,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _selectSample(i),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              onChanged: _onSourceChanged,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontFamilyFallback: ['Courier New', 'monospace'],
                fontSize: 13,
                height: 1.45,
              ),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Type mermaid source here...',
                filled: true,
                fillColor: colors.surfaceContainerLowest,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewPane() {
    final background = _mermaidTheme.background;
    final diagram = MermaidDiagram(
      source: _renderedSource,
      theme: _mermaidTheme,
      errorBuilder: (context, error) => _ErrorBanner(error: error),
    );
    return Container(
      color: Color(background.value),
      child: Stack(
        children: [
          Positioned.fill(
            child: _autoFit
                // Scale the diagram down (never up) to fit the pane.
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: diagram,
                    ),
                  )
                : InteractiveViewer(
                    boundaryMargin: const EdgeInsets.all(4000),
                    constrained: false,
                    minScale: 0.25,
                    maxScale: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: diagram,
                    ),
                  ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Tooltip(
              message: _autoFit
                  ? 'Auto-fit on — tap for free pan/zoom'
                  : 'Free pan/zoom — tap to fit to window',
              child: FloatingActionButton.small(
                heroTag: 'fit',
                onPressed: () => setState(() => _autoFit = !_autoFit),
                child: Icon(_autoFit ? Icons.fit_screen : Icons.pan_tool_alt),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: colors.onErrorContainer),
                  const SizedBox(width: 8),
                  Text(
                    'Diagram failed to render',
                    style: TextStyle(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                '$error',
                style: TextStyle(
                  color: colors.onErrorContainer,
                  fontSize: 13,
                  fontFamily: 'Menlo',
                  fontFamilyFallback: const ['Courier New', 'monospace'],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Style editor
// ---------------------------------------------------------------------------

/// Live editor for [core.MermaidTheme]: color swatches with hex fields plus a
/// font-size slider. Every change re-renders the preview immediately.
class ThemeEditor extends StatelessWidget {
  const ThemeEditor({
    super.key,
    required this.theme,
    required this.modified,
    required this.onChanged,
    required this.onReset,
  });

  final core.MermaidTheme theme;
  final bool modified;
  final ValueChanged<core.MermaidTheme> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, core.Color, core.MermaidTheme Function(core.Color))>[
      ('Node fill', theme.mainBkg, (c) => theme.copyWith(mainBkg: c)),
      ('Node border', theme.nodeBorder, (c) => theme.copyWith(nodeBorder: c)),
      ('Text', theme.textColor, (c) => theme.copyWith(textColor: c)),
      ('Lines', theme.lineColor, (c) => theme.copyWith(lineColor: c)),
      (
        'Arrowheads',
        theme.arrowheadColor,
        (c) => theme.copyWith(arrowheadColor: c)
      ),
      ('Cluster fill', theme.clusterBkg, (c) => theme.copyWith(clusterBkg: c)),
      (
        'Cluster border',
        theme.clusterBorder,
        (c) => theme.copyWith(clusterBorder: c)
      ),
      (
        'Edge label bg',
        theme.edgeLabelBackground,
        (c) => theme.copyWith(edgeLabelBackground: c)
      ),
      ('Title', theme.titleColor, (c) => theme.copyWith(titleColor: c)),
      ('Background', theme.background, (c) => theme.copyWith(background: c)),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Diagram styles',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: modified ? onReset : null,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset'),
            ),
            IconButton(
              tooltip: 'Close style editor',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Colors accept #RRGGBB or #AARRGGBB. Press enter to apply.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final (label, color, apply) in entries)
          _ColorRow(
            key: ValueKey('$label-${color.value}'),
            label: label,
            color: color,
            onColor: (c) => onChanged(apply(c)),
          ),
        const SizedBox(height: 16),
        Text('Font size: ${theme.fontSize.round()}',
            style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: theme.fontSize.clamp(10, 24),
          min: 10,
          max: 24,
          divisions: 14,
          onChanged: (v) => onChanged(theme.copyWith(fontSize: v)),
        ),
        const SizedBox(height: 8),
        Text(
          'Tip: per-node styles work in the source itself — try classDef, '
          'style and :::class statements.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ColorRow extends StatefulWidget {
  const _ColorRow({
    super.key,
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final core.Color color;
  final ValueChanged<core.Color> onColor;

  @override
  State<_ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<_ColorRow> {
  late final TextEditingController _controller =
      TextEditingController(text: _hex(widget.color));
  bool _invalid = false;

  static String _hex(core.Color c) {
    final v = c.value.toRadixString(16).padLeft(8, '0');
    return c.alpha == 0xff ? '#${v.substring(2)}' : '#$v';
  }

  void _submit(String text) {
    final parsed = core.Color.tryParse(text.trim());
    if (parsed == null) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    widget.onColor(parsed);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Color(widget.color.value),
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.label)),
          SizedBox(
            width: 110,
            child: TextField(
              key: ValueKey('hex-${widget.label}'),
              controller: _controller,
              onSubmitted: _submit,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                errorText: _invalid ? 'invalid' : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
