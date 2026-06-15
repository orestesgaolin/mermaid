/// The `/elk` page's interactive island: mounts [ElkFlutterApp] (real Flutter
/// widgets laid out by `elk_layout`) through `jaspr_flutter_embed`'s
/// [FlutterEmbedView], the same mechanism the comparison page uses for the
/// mermaid renderer.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_flutter_embed/jaspr_flutter_embed.dart';

// The embedded Flutter widget — real on the web build, a stub during static
// server pre-rendering (it pulls in dart:ui / Flutter, which the VM lacks).
@Import.onWeb('../flutter/elk_flutter_app.dart', show: [#ElkFlutterApp])
import 'elk_flutter_view.imports.dart';

@client
class ElkFlutterView extends StatelessComponent {
  const ElkFlutterView({super.key});

  @override
  Component build(BuildContext context) {
    return FlutterEmbedView(
      id: 'elk-flutter-canvas',
      classes: 'flutter-host',
      loader: div([.text('Loading Flutter…')]),
      widget: kIsWeb ? ElkFlutterApp() : null,
    );
  }
}
