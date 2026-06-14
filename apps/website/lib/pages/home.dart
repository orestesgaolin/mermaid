import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/compare_view.dart';

class Home extends StatelessComponent {
  const Home({super.key});

  @override
  Component build(BuildContext context) {
    return div(classes: 'page', [
      header(classes: 'hero', [
        div(classes: 'hero-top', [
          h1([.text('mermaid dart')]),
          a(
            classes: 'gh-link',
            href: 'https://github.com/orestesgaolin/mermaid',
            target: .blank,
            attributes: {'rel': 'noopener noreferrer'},
            [.text('GitHub ↗')],
          ),
        ]),
        p(classes: 'tagline', [
          .text('A pure-Dart port of mermaid.js with native Flutter '
              'rendering — same source, side by side with the original.'),
        ]),
      ]),
      const CompareView(),
      footer(classes: 'foot', [
        p([
          .text('Left: mermaid.js rendering in your browser. '
              'Right: the same source parsed, laid out and painted by '
              'mermaid dart inside an embedded Flutter web view.'),
        ]),
      ]),
    ]);
  }
}
