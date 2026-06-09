import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mermaid_core/mermaid_core.dart' as core;
import 'package:mermaid_flutter/mermaid_flutter.dart';

void main() {
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

  core.MermaidTheme get _mermaidTheme => widget.dark
      ? core.MermaidTheme.darkTheme
      : core.MermaidTheme.defaultTheme;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mermaid Dart'),
        actions: [
          IconButton(
            tooltip:
                widget.dark ? 'Switch to light theme' : 'Switch to dark theme',
            icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleDark,
          ),
          const SizedBox(width: 8),
        ],
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
    return Container(
      color: Color(background.value),
      child: InteractiveViewer(
        boundaryMargin: const EdgeInsets.all(4000),
        constrained: false,
        minScale: 0.25,
        maxScale: 4,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: MermaidDiagram(
            source: _renderedSource,
            theme: _mermaidTheme,
            errorBuilder: (context, error) => _ErrorBanner(error: error),
          ),
        ),
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
