// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:website/components/compare_view.dart' as _compare_view;
import 'package:website/components/elk_flutter_view.dart' as _elk_flutter_view;
import 'package:website/components/site_nav.dart' as _site_nav;
import 'package:website/constants/theme.dart' as _theme;
import 'package:website/pages/elk_demo.dart' as _elk_demo;
import 'package:website/app.dart' as _app;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _compare_view.CompareView: ClientTarget<_compare_view.CompareView>(
      'compare_view',
    ),
    _elk_flutter_view.ElkFlutterView:
        ClientTarget<_elk_flutter_view.ElkFlutterView>('elk_flutter_view'),
  },
  styles: () => [
    ..._theme.styles,
    ..._app.App.styles,
    ..._site_nav.SiteNav.styles,
    ..._elk_demo.ElkDemoPage.styles,
  ],
);
