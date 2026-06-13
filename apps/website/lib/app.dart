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
        css('.hero h1').styles(
          fontSize: 2.6.rem,
          margin: .only(bottom: 4.px),
          color: const Color('#4a3a8a'),
        ),
        css('.tagline').styles(
          color: const Color('#555566'),
          margin: .only(top: .zero, bottom: 24.px),
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
        css('.flutter-host').styles(
          padding: .zero,
          overflow: .hidden,
        ),
        css('.foot').styles(
          margin: .only(top: 24.px),
          color: const Color('#777788'),
          fontSize: 0.9.rem,
        ),
      ];
}
