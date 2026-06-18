import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/elk_flutter_view.dart';
import '../components/site_nav.dart';
import '../elk_demos.dart';
import '../generated/elk_readme.g.dart';

/// The essence of the embedded Flutter demo, shown beside the live canvas.
const _flutterSnippet = '''// elk is pure Dart, so it runs in Flutter.
final result = const ElkLayered().layout(ElkGraph(
  layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
  children: [
    for (final n in nodes)
      ElkNode(id: n.id, width: 168, height: 56),
  ],
  edges: [
    for (final (from, to) in edges)
      ElkEdge(id: '..', sources: [from], targets: [to]),
  ],
));

// Place each node as a real Flutter widget at ELK's coordinates…
Stack(children: [
  for (final spec in nodes)
    if (result.nodesById[spec.id] case final n?)
      Positioned(
        left: n.x, top: n.y,
        width: n.width, height: n.height,
        child: NodeCard(spec),      // a Material card
      ),
  // …and stroke ELK's orthogonal edge routes.
  CustomPaint(painter: EdgePainter(result.edges)),
]);''';

/// The `/elk` route: a standalone demo of the `elk` package — example
/// graphs laid out without mermaid and drawn straight to SVG, plus an
/// explanation of why the port exists and how to reuse it.
class ElkDemoPage extends StatelessComponent {
  const ElkDemoPage({super.key});

  @override
  Component build(BuildContext context) {
    final demos = buildElkDemos();
    return div(classes: 'page', [
      const SiteNav(active: SiteRoute.elk),
      header(classes: 'site-header', [
        div(classes: 'header-top', [
          h1([.text('elk')]),
          a(
            classes: 'gh-link',
            href: 'https://github.com/orestesgaolin/mermaid',
            target: .blank,
            attributes: const {'rel': 'noopener noreferrer'},
            [.text('GitHub ↗')],
          ),
        ]),
        p(classes: 'subtitle', [
          .text('A pure-Dart layered graph layout — the ELK algorithm, '
              'without mermaid, without elkjs.'),
        ]),
      ]),
      section(classes: 'intro', [
        p([
          .text('Every diagram below was laid out by the standalone '),
          strong([.text('elk')]),
          .text(' package and drawn straight to SVG — '),
          strong([.text('no mermaid, no diagram DSL')]),
          .text('. You hand it a graph of nodes and edges; it returns '
              'coordinates and orthogonal edge routes.'),
        ]),
      ]),
      div(classes: 'elk-cards', [
        for (final d in demos)
          figure(classes: d.wide ? 'elk-card elk-card-wide' : 'elk-card', [
            figcaption([
              h3([.text(d.title)]),
              p([.text(d.blurb)]),
            ]),
            div(classes: 'elk-svg-wrap', [RawText(d.svg)]),
          ]),
      ]),
      section(classes: 'intro', [
        h2([.text('Laid out as live Flutter widgets')]),
        p([
          .text('Because '),
          strong([.text('elk')]),
          .text(' is pure Dart, it runs inside Flutter too. Below, ELK '
              'positions '),
          em([.text('real, interactive Flutter widgets')]),
          .text(' — each card is a Material widget placed at the coordinates '
              'ELK computes, with the orthogonal edges drawn by a '),
          code([.text('CustomPainter')]),
          .text('. Drag to pan, scroll to zoom, tap a node to select it.'),
        ]),
      ]),
      div(classes: 'elk-flutter-row', [
        div(classes: 'elk-canvas-pane', [const ElkFlutterView()]),
        pre(classes: 'elk-code elk-code-side', [.text(_flutterSnippet)]),
      ]),
      // The canonical package documentation (options reference, examples,
      // validation) rendered from packages/elk/README.md. Regenerate
      // with `dart run tool/gen_readme_html.dart`.
      section(classes: 'intro elk-readme', [RawText(elkReadmeHtml)]),
      footer(classes: 'foot', [
        p([
          .text('Rendered from the elk package · part of the '),
          a(
            [.text('mermaid dart')],
            href: 'https://github.com/orestesgaolin/mermaid',
            target: .blank,
            attributes: const {'rel': 'noopener noreferrer'},
          ),
          .text(' project.'),
        ]),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
        css('.elk-cards').styles(
          display: .grid,
          gridTemplate: GridTemplate(
              columns: GridTracks([GridTrack(.fr(1)), GridTrack(.fr(1))])),
          gap: .all(20.px),
          margin: .only(top: 12.px, bottom: 8.px),
        ),
        css.media(MediaQuery.screen(maxWidth: 760.px), [
          css('.elk-cards').styles(
            gridTemplate:
                GridTemplate(columns: GridTracks([GridTrack(.fr(1))])),
          ),
        ]),
        css('.elk-card').styles(
          margin: .zero,
          border: .all(
              style: BorderStyle.solid, color: const Color('#e3ddf5'), width: 1.px),
          radius: .circular(12.px),
          overflow: .hidden,
        ),
        // The wide left-to-right graph spans both grid columns.
        css('.elk-card-wide').styles(
          raw: {'grid-column': '1 / -1'},
        ),
        css('.elk-card figcaption').styles(padding: .only(
            top: 12.px, left: 14.px, right: 14.px)),
        css('.elk-card h3').styles(
          color: const Color('#4a3a8a'),
          margin: .only(bottom: 4.px),
          fontSize: 1.1.rem,
        ),
        css('.elk-card figcaption p').styles(
          color: const Color('#555566'),
          fontSize: 0.9.rem,
          margin: .zero,
        ),
        css('.elk-svg-wrap').styles(
          padding: .all(14.px),
          display: .flex,
          justifyContent: .center,
        ),
        css('.elk-svg-wrap svg').styles(
          maxWidth: 100.percent,
          height: .auto,
        ),
        css('.node-label').styles(
          raw: {'fill': '#33335a', 'font-size': '14px'},
        ),
        css('.cluster-label').styles(
          raw: {'fill': '#4a3a8a', 'font-size': '12px', 'font-weight': '600'},
        ),
        css('.elk-code').styles(
          backgroundColor: const Color('#f6f4fc'),
          padding: .all(14.px),
          radius: .circular(8.px),
          fontSize: 0.85.rem,
          overflow: .auto,
          border: .all(
              style: BorderStyle.solid, color: const Color('#e3ddf5'), width: 1.px),
        ),
        // Live Flutter canvas beside its source: two columns on desktop,
        // stacked on mobile.
        css('.elk-flutter-row').styles(
          display: .grid,
          gridTemplate: GridTemplate(
              columns: GridTracks([GridTrack(.fr(1)), GridTrack(.fr(1))])),
          gap: .all(16.px),
          alignItems: .stretch,
          margin: .only(top: 12.px, bottom: 8.px),
        ),
        css.media(MediaQuery.screen(maxWidth: 760.px), [
          css('.elk-flutter-row').styles(
            gridTemplate:
                GridTemplate(columns: GridTracks([GridTrack(.fr(1))])),
          ),
        ]),
        // The embedded Flutter canvas: a bordered, fixed-height surface. The
        // FlutterEmbedView wraps the flutter-view in a div which flexbox would
        // otherwise collapse, so make the host a block that fills the pane.
        css('.elk-canvas-pane').styles(
          height: 460.px,
          border: .all(
              style: BorderStyle.solid, color: const Color('#e3ddf5'), width: 1.px),
          radius: .circular(12.px),
          overflow: .hidden,
          backgroundColor: Colors.white,
        ),
        css('.elk-canvas-pane .flutter-host').styles(
          display: .block,
          width: 100.percent,
          height: 100.percent,
        ),
        css('.elk-canvas-pane .flutter-host > div').styles(
          width: 100.percent,
          height: 100.percent,
        ),
        // Source shown beside the canvas: matches its height and scrolls.
        css('.elk-code-side').styles(
          height: 460.px,
          margin: .zero,
          boxSizing: .borderBox,
        ),
        // README rendered from markdown: headings, tables, code blocks.
        css('.elk-readme h2').styles(
          fontSize: 1.4.rem,
          color: const Color('#4a3a8a'),
          margin: .only(top: 28.px, bottom: 6.px),
        ),
        css('.elk-readme h3').styles(
          fontSize: 1.1.rem,
          color: const Color('#4a3a8a'),
          margin: .only(top: 18.px, bottom: 4.px),
        ),
        css('.elk-readme code').styles(
          backgroundColor: const Color('#f0edf9'),
          padding: .symmetric(vertical: 1.px, horizontal: 5.px),
          radius: .circular(4.px),
          fontSize: 0.9.em,
          fontFamily: .list([
            FontFamily('ui-monospace'),
            FontFamily('SFMono-Regular'),
            FontFamily('Menlo'),
            FontFamilies.monospace,
          ]),
        ),
        css('.elk-readme pre').styles(
          backgroundColor: const Color('#f6f4fc'),
          padding: .all(14.px),
          radius: .circular(8.px),
          fontSize: 0.85.rem,
          overflow: .auto,
          border: .all(
              style: BorderStyle.solid, color: const Color('#e3ddf5'), width: 1.px),
        ),
        css('.elk-readme pre code').styles(
          backgroundColor: Colors.transparent,
          padding: .zero,
        ),
        css('.elk-readme table').styles(
          width: 100.percent,
          margin: .only(top: 8.px, bottom: 12.px),
          fontSize: 0.92.rem,
          raw: {'border-collapse': 'collapse'},
        ),
        css('.elk-readme th, .elk-readme td').styles(
          border: .all(
              style: BorderStyle.solid, color: const Color('#e3ddf5'), width: 1.px),
          padding: .symmetric(vertical: 6.px, horizontal: 10.px),
          raw: {'text-align': 'left'},
        ),
        css('.elk-readme th').styles(
          backgroundColor: const Color('#f6f4fc'),
          color: const Color('#4a3a8a'),
        ),
        css('.elk-readme blockquote').styles(
          margin: .only(top: 10.px, bottom: 10.px),
          padding: .only(left: 14.px),
          border: .only(
              left: BorderSide(color: const Color('#c8bfe8'), width: 3.px)),
          color: const Color('#555566'),
        ),
      ];
}
