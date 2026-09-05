import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/compare_view.dart';
import '../components/site_nav.dart';

class Home extends StatelessComponent {
  const Home({super.key});

  @override
  Component build(BuildContext context) {
    return div(classes: 'page', [
      const SiteNav(active: SiteRoute.comparison),
      header(classes: 'site-header', [
        div(classes: 'header-top', [
          h1([.text('mermaid dart')]),
          div(classes: 'header-links', [
            a(
              classes: 'gh-link',
              href: 'https://pub.dev/packages/mermaid_flutter',
              target: .blank,
              attributes: const {'rel': 'noopener noreferrer'},
              [.text('pub.dev ↗')],
            ),
            a(
              classes: 'gh-link',
              href: 'https://github.com/orestesgaolin/mermaid',
              target: .blank,
              attributes: const {'rel': 'noopener noreferrer'},
              [.text('GitHub ↗')],
            ),
          ]),
        ]),
        p(classes: 'subtitle', [
          .text(
            'A pure-Dart port of mermaid.js with native Flutter '
            'rendering.',
          ),
        ]),
      ]),
      section(classes: 'intro', [
        p([
          strong([.text('mermaid dart')]),
          .text(' is a pure-Dart port of '),
          a(
            [.text('mermaid.js')],
            href: 'https://mermaid.js.org',
            target: .blank,
            attributes: const {'rel': 'noopener noreferrer'},
          ),
          .text(
            '. It detects, parses and lays out the same diagram source '
            'into a backend-agnostic ',
          ),
          strong([.text('render scene')]),
          .text(
            ', then paints that scene natively - no JavaScript, no '
            'WebView, no SVG round-trip. This page renders samples side by side: the original ',
          ),
          strong([.text('mermaid.js')]),
          .text(' in your browser (left) and '),
          strong([.text('mermaid dart')]),
          .text(' inside an embedded Flutter island.'),
        ]),
        p([
          .text('The TeX math labels in diagrams are rendered with '),
          strong([.text('katex')]),
          .text(' - a Dart port of '),
          a(
            [.text('KaTeX')],
            href: 'https://katex.org',
            target: .blank,
            attributes: const {'rel': 'noopener noreferrer'},
          ),
          .text(
            ' that brings its own three-way renderer comparison. mermaid '
            'dart reuses that backend-agnostic box tree to lay out math '
            'natively in Flutter.',
          ),
        ]),
        p([
          .text('The '),
          strong([.text('ELK layout')]),
          .text(' option is powered by '),
          strong([.text('elk')]),
          .text(
            ' - a standalone, Dart port of the Eclipse Layout '
            'Kernel\'s layered algorithm (orthogonal edges, clusters, no '
            'elkjs, no JavaScript). It\'s mostly an approximation. It is reusable on its own for any graph '
            'layout, such as package dependency visualizations. Explore it '
            'on the ',
          ),
          a([.text('ELK layout')], href: 'elk'),
          .text(' page.'),
        ]),
      ]),
      section(classes: 'theme-bridge', [
        div(classes: 'theme-bridge-copy', [
          div(classes: 'theme-bridge-kicker', [.text('Flutter integration')]),
          h2([.text('Follow ThemeData with one call')]),
          p([
            .text(
              'The Flutter preview uses native Mermaid colors by default. '
              'Enable Material theme to map the active Material color and '
              'text roles into every Mermaid diagram family. The light/dark '
              'button switches brightness independently.',
            ),
          ]),
          p([
            .text('Add '),
            a(
              [
                code([.text('mermaid_flutter')]),
              ],
              href: 'https://pub.dev/packages/mermaid_flutter',
              target: .blank,
              attributes: const {'rel': 'noopener noreferrer'},
            ),
            .text(' from pub.dev to use the same widgets in your app.'),
          ]),
        ]),
        pre(classes: 'theme-bridge-code', [
          code([
            .text(
              'MermaidView(\n'
              '  source: source,\n'
              '  theme: MaterialMermaidTheme.fromTheme(\n'
              '    Theme.of(context),\n'
              '  ),\n'
              ')',
            ),
          ]),
        ]),
      ]),
      const CompareView(),
      footer(classes: 'foot', [
        p([
          .text(
            'Left: mermaid.js rendering in your browser. '
            'Right: the same source parsed, laid out and painted by '
            'mermaid dart inside an embedded Flutter web view.',
          ),
        ]),
      ]),
    ]);
  }
}
