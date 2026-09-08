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
          .text(
            'A pure-Dart layered graph layout beside a precomputed elkjs '
            'reference.',
          ),
        ]),
      ]),
      section(classes: 'intro', [
        p([
          .text('Each example runs through the standalone '),
          strong([.text('elk')]),
          .text(' package and is shown beside a precomputed '),
          strong([.text('elkjs')]),
          .text(' result for the same graph, options, and SVG renderer — '),
          strong([.text('no mermaid, no diagram DSL')]),
          .text(
            '. Both panels use the same coordinate scale, so spacing and '
            'routing differences stay visible. The shared preview renderer '
            'omits arrowheads in both panels. This is a behavioral comparison, '
            'not a claim of pixel or layout parity.',
          ),
        ]),
        p(classes: 'elk-bounds-note', [
          .text(
            'The dashed amber rectangle marks the bounds returned by '
            'each layout engine. Select Actual size to inspect routes closely; large diagrams then scroll inside their panel.',
          ),
        ]),
      ]),
      div(classes: 'elk-cards', [
        for (final d in demos)
          figure(classes: 'elk-card elk-card-wide', [
            figcaption([
              h3([.text(d.title)]),
              p([.text(d.blurb)]),
              if (d.comparisonNote != null)
                p(classes: 'elk-comparison-note', [
                  .text(d.comparisonNote!),
                  if (d.trackingIssue != null) ...[
                    .text(' '),
                    a(
                      href:
                          'https://github.com/orestesgaolin/mermaid/issues/${d.trackingIssue}',
                      [.text('Track #${d.trackingIssue}')],
                    ),
                  ],
                ]),
              label(classes: 'elk-size-control', [
                input(type: InputType.checkbox, classes: 'elk-actual-size'),
                .text(' Actual size (both panels)'),
              ]),
            ]),
            div(classes: 'elk-compare', [
              _enginePanel(
                label: 'Dart ELK',
                dimensions: d.dimensions,
                svg: d.svg,
              ),
              _enginePanel(
                label: d.version.isEmpty
                    ? 'elkjs reference'
                    : 'elkjs ${d.version}',
                dimensions: d.referenceDimensions,
                svg: d.referenceSvg,
                error: d.referenceError,
              ),
            ]),
            details(classes: 'elk-input', [
              summary([.text('Input graph JSON and layout options')]),
              pre(classes: 'elk-code', [
                code([.text(d.inputJson)]),
              ]),
            ]),
          ]),
      ]),
      section(classes: 'intro', [
        h2([.text('Laid out as live Flutter widgets')]),
        p([
          .text('Because '),
          strong([.text('elk')]),
          .text(
            ' is pure Dart, it runs inside Flutter too. Below, ELK '
            'positions ',
          ),
          em([.text('real, interactive Flutter widgets')]),
          .text(
            ' — each card is a Material widget placed at the coordinates '
            'ELK computes, with the orthogonal edges drawn by a ',
          ),
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

  Component _enginePanel({
    required String label,
    required String dimensions,
    String? svg,
    String? error,
  }) => section(classes: 'elk-engine-panel', [
    div(classes: 'elk-engine-heading', [
      strong([.text(label)]),
      if (dimensions.isNotEmpty)
        span(classes: 'elk-dimensions', [.text('$dimensions units')]),
    ]),
    if (svg != null)
      div(classes: 'elk-svg-wrap', [RawText(svg)])
    else
      div(classes: 'elk-reference-error', [
        strong([.text('Reference unavailable')]),
        if (error != null && error.isNotEmpty) p([.text(error)]),
      ]),
  ]);

  @css
  static List<StyleRule> get styles => [
    css('.elk-comparison-note').styles(
      raw: {
        'padding': '10px 12px',
        'background': '#f6f4fc',
        'border-left': '3px solid #9b8fd6',
        'font-size': '13px',
        'line-height': '1.5',
      },
    ),
    css('.elk-cards').styles(
      display: .grid,
      gridTemplate: GridTemplate(columns: GridTracks([GridTrack(.fr(1))])),
      gap: .all(20.px),
      margin: .only(top: 12.px, bottom: 8.px),
    ),
    css('.elk-card').styles(
      raw: {'min-width': '0'},
      margin: .zero,
      border: .all(
        style: BorderStyle.solid,
        color: const Color('#e3ddf5'),
        width: 1.px,
      ),
      radius: .circular(12.px),
      overflow: .hidden,
    ),
    // The wide left-to-right graph spans both grid columns.
    css('.elk-card-wide').styles(raw: {'grid-column': '1 / -1'}),
    css('.elk-card figcaption').styles(
      padding: .only(top: 12.px, left: 14.px, right: 14.px),
    ),
    css('.elk-card h3').styles(
      color: const Color('#4a3a8a'),
      margin: .only(bottom: 4.px),
      fontSize: 1.1.rem,
    ),
    css(
      '.elk-card figcaption p',
    ).styles(color: const Color('#555566'), fontSize: 0.9.rem, margin: .zero),
    css(
      '.elk-bounds-note',
    ).styles(color: const Color('#75551f'), fontSize: 0.9.rem),
    css('.elk-compare').styles(
      display: .grid,
      gridTemplate: GridTemplate(
        columns: GridTracks([GridTrack(.fr(1)), GridTrack(.fr(1))]),
      ),
      gap: .all(1.px),
      backgroundColor: const Color('#e3ddf5'),
      border: .only(
        top: BorderSide(color: const Color('#e3ddf5'), width: 1.px),
        bottom: BorderSide(color: const Color('#e3ddf5'), width: 1.px),
      ),
      raw: {'min-width': '0'},
    ),
    css('.elk-engine-panel').styles(
      backgroundColor: Colors.white,
      overflow: .hidden,
      raw: {'min-width': '0'},
    ),
    css('.elk-engine-heading').styles(
      display: .flex,
      justifyContent: .spaceBetween,
      alignItems: .center,
      gap: .all(12.px),
      padding: .symmetric(vertical: 9.px, horizontal: 12.px),
      backgroundColor: const Color('#f6f4fc'),
      color: const Color('#4a3a8a'),
      fontSize: 0.88.rem,
    ),
    css('.elk-dimensions').styles(
      color: const Color('#666174'),
      fontSize: 0.78.rem,
      raw: {'white-space': 'nowrap'},
    ),
    css('.elk-svg-wrap').styles(
      overflow: .auto,
      padding: .all(14.px),
      display: .flex,
      justifyContent: .start,
      raw: {'max-height': '520px', 'box-sizing': 'border-box'},
    ),
    css(
      '.elk-svg-wrap svg',
    ).styles(raw: {'width': '100%', 'height': 'auto', 'max-width': 'none'}),
    css(
      '.elk-card:has(.elk-actual-size:checked) .elk-svg-wrap svg',
    ).styles(raw: {'width': 'auto'}),
    css('.elk-size-control').styles(
      raw: {
        'display': 'inline-flex',
        'align-items': 'center',
        'gap': '6px',
        'font-size': '13px',
        'margin-top': '8px',
        'cursor': 'pointer',
      },
    ),
    css('.elk-reference-error').styles(
      padding: .all(18.px),
      color: const Color('#7a3f35'),
      backgroundColor: const Color('#fff8f2'),
      raw: {'min-height': '120px', 'box-sizing': 'border-box'},
    ),
    css('.elk-reference-error p').styles(
      margin: .only(top: 6.px),
      fontSize: 0.85.rem,
    ),
    css('.elk-input').styles(
      padding: .symmetric(vertical: 10.px, horizontal: 14.px),
      backgroundColor: const Color('#fbfaff'),
      raw: {'min-width': '0'},
    ),
    css('.elk-input summary').styles(
      color: const Color('#4a3a8a'),
      fontSize: 0.88.rem,
      raw: {'cursor': 'pointer', 'font-weight': '600'},
    ),
    css('.elk-input .elk-code').styles(
      margin: .only(top: 10.px, bottom: 0.px),
      maxWidth: 100.percent,
      raw: {'max-height': '360px', 'box-sizing': 'border-box'},
    ),
    css.media(MediaQuery.screen(maxWidth: 760.px), [
      css('.elk-compare').styles(
        gridTemplate: GridTemplate(columns: GridTracks([GridTrack(.fr(1))])),
      ),
    ]),
    css('.node-label').styles(raw: {'fill': '#33335a', 'font-size': '14px'}),
    css(
      '.edge-label, .port-label',
    ).styles(raw: {'fill': '#4a3a8a', 'font-size': '11px'}),
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
        style: BorderStyle.solid,
        color: const Color('#e3ddf5'),
        width: 1.px,
      ),
    ),
    // Live Flutter canvas beside its source: two columns on desktop,
    // stacked on mobile.
    css('.elk-flutter-row').styles(
      display: .grid,
      gridTemplate: GridTemplate(
        columns: GridTracks([GridTrack(.fr(1)), GridTrack(.fr(1))]),
      ),
      gap: .all(16.px),
      alignItems: .stretch,
      margin: .only(top: 12.px, bottom: 8.px),
    ),
    css.media(MediaQuery.screen(maxWidth: 760.px), [
      css('.elk-flutter-row').styles(
        gridTemplate: GridTemplate(columns: GridTracks([GridTrack(.fr(1))])),
      ),
    ]),
    // The embedded Flutter canvas: a bordered, fixed-height surface. The
    // FlutterEmbedView wraps the flutter-view in a div which flexbox would
    // otherwise collapse, so make the host a block that fills the pane.
    css('.elk-canvas-pane').styles(
      height: 460.px,
      border: .all(
        style: BorderStyle.solid,
        color: const Color('#e3ddf5'),
        width: 1.px,
      ),
      radius: .circular(12.px),
      overflow: .hidden,
      backgroundColor: Colors.white,
    ),
    css(
      '.elk-canvas-pane .flutter-host',
    ).styles(display: .block, width: 100.percent, height: 100.percent),
    css(
      '.elk-canvas-pane .flutter-host > div',
    ).styles(width: 100.percent, height: 100.percent),
    // Source shown beside the canvas: matches its height and scrolls.
    css(
      '.elk-code-side',
    ).styles(height: 460.px, margin: .zero, boxSizing: .borderBox),
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
        style: BorderStyle.solid,
        color: const Color('#e3ddf5'),
        width: 1.px,
      ),
    ),
    css(
      '.elk-readme pre code',
    ).styles(backgroundColor: Colors.transparent, padding: .zero),
    css('.elk-readme table').styles(
      display: .block,
      overflow: .auto,
      maxWidth: 100.percent,
      width: 100.percent,
      margin: .only(top: 8.px, bottom: 12.px),
      fontSize: 0.92.rem,
      raw: {'border-collapse': 'collapse'},
    ),
    css('.elk-readme th, .elk-readme td').styles(
      border: .all(
        style: BorderStyle.solid,
        color: const Color('#e3ddf5'),
        width: 1.px,
      ),
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
        left: BorderSide(color: const Color('#c8bfe8'), width: 3.px),
      ),
      color: const Color('#555566'),
    ),
  ];
}
