import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'pages/home.dart';

/// Server-rendered shell; the interactive comparison inside [Home] is the
/// only client island (see CompareView's @client annotation).
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) {
    return const Home();
  }

  @css
  static List<StyleRule> get styles => [
        css('.page').styles(
          maxWidth: 1240.px,
          margin: .symmetric(horizontal: .auto),
          padding: .all(24.px),
        ),
        css('.site-header').styles(
          margin: .only(bottom: 24.px),
        ),
        // Title row: heading on the left, GitHub pill on the right.
        css('.header-top').styles(
          display: .flex,
          alignItems: .baseline,
          justifyContent: .spaceBetween,
          flexWrap: .wrap,
          gap: .all(12.px),
        ),
        css('.site-header h1').styles(
          fontSize: 2.4.rem,
          margin: .only(bottom: 4.px),
          color: const Color('#4a3a8a'),
        ),
        // GitHub pill in the header (shared shape with the katex site).
        css('.gh-link').styles(
          padding: .symmetric(vertical: 6.px, horizontal: 14.px),
          radius: .circular(16.px),
          border: .all(
              style: BorderStyle.solid, color: const Color('#c8bfe8'), width: 1.px),
          backgroundColor: Colors.white,
          color: const Color('#4a3a8a'),
          fontSize: 0.95.rem,
          fontWeight: .w600,
          whiteSpace: .noWrap,
          textDecoration: const TextDecoration(line: TextDecorationLine.none),
        ),
        css('.gh-link:hover').styles(
          backgroundColor: const Color('#ececff'),
        ),
        css('.actions').styles(
          display: .flex,
          alignItems: .center,
          flexWrap: .wrap,
          gap: .all(10.px),
          margin: .only(top: 8.px),
        ),
        css('.report-btn').styles(
          padding: .symmetric(vertical: 6.px, horizontal: 14.px),
          radius: .circular(16.px),
          border: .all(
              style: BorderStyle.solid, color: const Color('#e0a0a0'), width: 1.px),
          backgroundColor: const Color('#fff5f5'),
          color: const Color('#9a2a2a'),
          fontSize: 0.95.rem,
          cursor: .pointer,
        ),
        css('.report-btn:hover').styles(
          backgroundColor: const Color('#ffe9e9'),
        ),
        css('.actions-hint').styles(
          fontSize: 0.85.rem,
          color: const Color('#999'),
        ),
        css('.subtitle').styles(
          color: const Color('#555566'),
          fontSize: 1.05.rem,
          margin: .only(top: 4.px, bottom: .zero),
        ),
        // Explanation / "what is this" section at the top (shared shape with
        // the katex site).
        css('.intro').styles(
          maxWidth: 880.px,
          margin: .only(bottom: 24.px),
        ),
        css('.intro p').styles(
          margin: .only(bottom: 10.px),
          color: const Color('#444'),
          fontSize: 1.rem,
          lineHeight: 1.6.em,
        ),
        css('.intro a').styles(color: const Color('#4a3a8a')),
        css('.intro .intro-links').styles(margin: .only(top: 8.px)),
        // Primary call-to-action button (accent-filled).
        css('.intro .intro-links a').styles(
          display: .inlineBlock,
          padding: .symmetric(vertical: 8.px, horizontal: 16.px),
          radius: .circular(8.px),
          color: Colors.white,
          backgroundColor: const Color('#4a3a8a'),
          fontSize: 0.95.rem,
          fontWeight: .w600,
          textDecoration: const TextDecoration(line: TextDecorationLine.none),
        ),
        css('.intro .intro-links a:hover').styles(
          backgroundColor: const Color('#382c69'),
        ),
        css('.cat-label').styles(
          textTransform: .upperCase,
          fontSize: 0.72.rem,
          fontWeight: .w700,
          letterSpacing: 0.06.em,
          color: const Color('#8a82a8'),
          margin: .only(top: 12.px, bottom: 6.px),
        ),
        css('.chips').styles(
          display: .flex,
          flexWrap: .wrap,
          gap: .all(8.px),
          margin: .only(bottom: 8.px),
        ),
        css('.doc').styles(
          margin: .only(top: 18.px, bottom: 6.px),
        ),
        css('.doc h2').styles(
          fontSize: 1.5.rem,
          margin: .only(bottom: 4.px),
          color: const Color('#4a3a8a'),
        ),
        css('.layout-row').styles(
          display: .flex,
          alignItems: .center,
          flexWrap: .wrap,
          gap: .all(8.px),
          margin: .only(bottom: 10.px),
        ),
        css('.layout-label').styles(
          fontSize: 0.8.rem,
          fontWeight: .w700,
          textTransform: .upperCase,
          letterSpacing: 0.05.em,
          color: const Color('#8a82a8'),
        ),
        css('.layout-hint').styles(
          fontSize: 0.85.rem,
          color: const Color('#999'),
        ),
        css('.doc-desc').styles(
          margin: .only(top: .zero, bottom: 10.px),
          color: const Color('#555566'),
          fontSize: 1.02.rem,
          maxWidth: 760.px,
        ),
        css('.chip').styles(
          padding: .symmetric(vertical: 6.px, horizontal: 14.px),
          radius: .circular(16.px),
          border: .all(style: BorderStyle.solid, color: const Color('#c8bfe8'), width: 1.px),
          backgroundColor: Colors.white,
          fontSize: 0.95.rem,
          cursor: .pointer,
        ),
        css('.chip.selected').styles(
          backgroundColor: const Color('#ececff'),
          fontWeight: .w600,
        ),
        css('.source').styles(
          backgroundColor: const Color('#f6f4fc'),
          padding: .all(14.px),
          radius: .circular(8.px),
          fontSize: 0.85.rem,
          overflow: .auto,
          maxHeight: 220.px,
          border: .all(style: BorderStyle.solid, color: const Color('#e3ddf5'), width: 1.px),
        ),
        // Editable source box: full-width monospace textarea, edits both
        // previews live.
        css('.editor').styles(
          display: .block,
          width: 100.percent,
          boxSizing: .borderBox,
          fontFamily: .list([FontFamily('ui-monospace'), FontFamily('SFMono-Regular'), FontFamily('Menlo'), FontFamilies.monospace]),
          lineHeight: 1.5.em,
          color: const Color('#33335a'),
          raw: {'resize': 'vertical'},
        ),
        css('.editor:focus').styles(
          border: .all(style: BorderStyle.solid, color: const Color('#9b8fd6'), width: 1.px),
          raw: {'outline': 'none'},
        ),
        css('.panes').styles(
          display: .grid,
          gridTemplate: GridTemplate(columns: GridTracks([GridTrack(.fr(1)), GridTrack(.fr(1))])),
          gap: .all(16.px),
          margin: .only(top: 8.px),
        ),
        css.media(MediaQuery.screen(maxWidth: 900.px), [
          css('.panes').styles(
            gridTemplate: GridTemplate(columns: GridTracks([GridTrack(.fr(1))])),
          ),
        ]),
        css('.pane').styles(
          border: .all(style: BorderStyle.solid, color: const Color('#e3ddf5'), width: 1.px),
          radius: .circular(10.px),
          overflow: .hidden,
        ),
        css('.pane-title').styles(
          padding: .symmetric(vertical: 8.px, horizontal: 12.px),
          backgroundColor: const Color('#f6f4fc'),
          fontWeight: .w600,
          fontSize: 0.9.rem,
          color: const Color('#4a3a8a'),
        ),
        css('.pane-body').styles(
          height: 480.px,
          padding: .all(8.px),
          display: .flex,
          alignItems: .center,
          justifyContent: .center,
          overflow: .auto,
          backgroundColor: Colors.white,
        ),
        css('.pane-body svg').styles(
          maxWidth: 100.percent,
          maxHeight: 100.percent,
        ),
        // FlutterEmbedView mounts the Flutter view inside a wrapper div. The
        // pane-body centres its child with flexbox, which collapses that
        // wrapper (and the flutter-view) to width 0 — so render as a plain
        // block and make the wrapper fill the pane.
        css('.flutter-host').styles(
          display: .block,
          padding: .zero,
          overflow: .hidden,
        ),
        css('.flutter-host > div').styles(
          width: 100.percent,
          height: 100.percent,
        ),
        // The embedded Flutter pane promoted to a full-page overlay (the
        // viewer's popup button toggles this — see web/embed_bridge.js).
        css('.flutter-host.mermaid-fullscreen').styles(
          position: .fixed(top: .zero, left: .zero),
          width: 100.vw,
          height: 100.vh,
          backgroundColor: Colors.white,
          raw: {'z-index': '2000'},
        ),
        css('#mermaid-fs-close').styles(
          position: .fixed(top: 16.px, right: 16.px),
          padding: .symmetric(vertical: 8.px, horizontal: 14.px),
          radius: .circular(8.px),
          border: .all(
              style: BorderStyle.solid,
              color: const Color('#c8bfe8'),
              width: 1.px),
          backgroundColor: Colors.white,
          color: const Color('#4a3a8a'),
          fontSize: 0.95.rem,
          fontWeight: .w600,
          cursor: .pointer,
          raw: {'z-index': '2001'},
        ),
        css('.foot').styles(
          margin: .only(top: 32.px),
          padding: .only(top: 16.px),
          border: .only(
            top: BorderSide(color: const Color('#e2e2e2'), width: 1.px),
          ),
          color: const Color('#777788'),
          fontSize: 0.9.rem,
        ),
      ];
}
