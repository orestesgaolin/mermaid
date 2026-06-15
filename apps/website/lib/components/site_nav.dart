/// Shared header navigation linking the site's pages plus the sibling katex
/// comparison site.
///
/// Rendered at the top of every route (`/` comparison and `/elk` layout demo).
/// Uses **base-relative** hrefs (`.` for home, `elk` for the demo) so they
/// resolve against the page's `<base href>` and keep working under the
/// `/mermaid/` sub-path on GitHub Pages.
///
/// These are plain full-page `<a>` links (not client-side SPA navigation): the
/// site is a static multi-page build where each route is its own pre-rendered
/// HTML file hosting an embedded Flutter engine that must boot fresh per page
/// load. (Mirrors the katex comparison site's `SiteNav`.)
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Identifies which route is currently active, to highlight its nav link.
enum SiteRoute { comparison, elk }

/// The shared top navigation bar.
class SiteNav extends StatelessComponent {
  const SiteNav({required this.active, super.key});

  /// The currently-active route (its link is marked `aria-current`).
  final SiteRoute active;

  @override
  Component build(BuildContext context) {
    return nav(classes: 'site-nav', [
      a(
        // `.` resolves against the page's <base href> to the site root, so the
        // home link works from `/elk/` and under the Pages sub-path.
        href: '.',
        classes:
            active == SiteRoute.comparison ? 'nav-link active' : 'nav-link',
        attributes: active == SiteRoute.comparison
            ? const {'aria-current': 'page'}
            : const {},
        [.text('Comparison')],
      ),
      a(
        href: 'elk',
        classes: active == SiteRoute.elk ? 'nav-link active' : 'nav-link',
        attributes:
            active == SiteRoute.elk ? const {'aria-current': 'page'} : const {},
        [.text('ELK layout')],
      ),
      // Cross-link to the sibling katex renderer comparison site (which shares
      // this layout and supplies mermaid dart's TeX math rendering).
      a(
        classes: 'nav-link external',
        href: 'https://orestesgaolin.github.io/katex/',
        target: .blank,
        attributes: const {'rel': 'noopener noreferrer'},
        [.text('KaTeX comparison ↗')],
      ),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
        css('.site-nav', [
          css('&').styles(
            display: .flex,
            padding: .symmetric(vertical: 12.px),
            margin: .only(bottom: 8.px),
            border: .only(
              bottom: BorderSide(color: const Color('#e2e2e2'), width: 1.px),
            ),
            gap: .all(8.px),
            alignItems: .center,
          ),
          css('.nav-link', [
            css('&').styles(
              padding: .symmetric(horizontal: 12.px, vertical: 6.px),
              radius: .circular(6.px),
              color: const Color('#4a3a8a'),
              textDecoration:
                  const TextDecoration(line: TextDecorationLine.none),
              fontSize: 0.95.rem,
              fontWeight: .w500,
            ),
            css('&:hover').styles(backgroundColor: const Color('#ececff')),
            css('&.active').styles(
              color: const Color('#fff'),
              backgroundColor: const Color('#4a3a8a'),
            ),
            // Push the cross-site link to the far right of the bar.
            css('&.external').styles(margin: .only(left: .auto)),
          ]),
        ]),
      ];
}
