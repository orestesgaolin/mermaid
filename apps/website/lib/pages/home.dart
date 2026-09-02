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
          a(
            classes: 'gh-link',
            href: 'https://github.com/orestesgaolin/mermaid',
            target: .blank,
            attributes: {'rel': 'noopener noreferrer'},
            [.text('GitHub ↗')],
          ),
        ]),
        p(classes: 'subtitle', [
          .text(
            'A pure-Dart port of mermaid.js with native Flutter '
            'rendering — same source, side by side with the original.',
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
            ', then paints that scene natively — no JavaScript, no '
            'WebView, no SVG round-trip. This page renders each sample two '
            'ways: the original ',
          ),
          strong([.text('mermaid.js')]),
          .text(' in your browser (left) and '),
          strong([.text('mermaid dart')]),
          .text(
            ' inside an embedded Flutter web view (right), so any '
            'difference is obvious at a glance.',
          ),
        ]),
        p([
          .text('The TeX math labels in diagrams are rendered with '),
          strong([.text('katex')]),
          .text(' — the same pure-Dart port of '),
          a(
            [.text('KaTeX')],
            href: 'https://katex.org',
            target: .blank,
            attributes: const {'rel': 'noopener noreferrer'},
          ),
          .text(
            ' that powers its own three-way renderer comparison. mermaid '
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
            ' — a standalone, pure-Dart port of the Eclipse Layout '
            'Kernel\'s layered algorithm (orthogonal edges, clusters, no '
            'elkjs, no JavaScript). It is reusable on its own for any graph '
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
              'The Flutter preview below maps the active Material color '
              'and text roles into every Mermaid diagram family. For '
              'samples without an explicit theme directive, use its '
              'light/dark button to switch ThemeData and repaint the same '
              'source immediately.',
            ),
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
