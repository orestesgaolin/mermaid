/// The entrypoint for the **server** environment.
///
/// The [main] method will only be executed on the server during pre-rendering.
/// To run code on the client, check the `main.client.dart` file.
library;

import 'package:jaspr/dom.dart';
// Server-specific Jaspr import.
import 'package:jaspr/server.dart';

// Imports the [App] component.
import 'app.dart';

// This file is generated automatically by Jaspr, do not remove or edit.
import 'main.server.options.dart';

void main() {
  // Initializes the server environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultServerOptions,
  );

  // Starts the app.
  //
  // [Document] renders the root document structure (<html>, <head> and <body>)
  // with the provided parameters and components.
  runApp(Document(
    title: 'mermaid dart — comparison',
    head: [
      // Flutter bootstrap for jaspr_flutter_embed; jaspr_builder fills the
      // {{flutter_js}} / {{flutter_build_config}} placeholders at build time.
      script(src: 'flutter_bootstrap.js', attributes: {'async': ''}),
      script(src: 'embed_bridge.js', attributes: {'type': 'module'}),
    ],
    styles: [
      // Shared site font with the sibling katex comparison site (Inter).
      css.import('https://fonts.googleapis.com/css?family=Inter:400,500,600,700'),
      // Each style rule takes a valid css selector and a set of styles.
      // Styles are defined using type-safe css bindings and can be freely chained and nested.
      css('html, body').styles(
        width: 100.percent,
        minHeight: 100.vh,
        padding: .zero,
        margin: .zero,
        color: const Color('#1a1a1a'),
        fontFamily: const .list([FontFamily('Inter'), FontFamilies.sansSerif]),
      ),
    ],
    body: App(),
  ));
}
