// GENERATED — do not edit. Source: packages/elk/README.md
// Regenerate: dart run tool/gen_readme_html.dart
library;

/// The elk README rendered to HTML (minus its top-level title).
const elkReadmeHtml = r'''
<p><code>elk</code> is a pure Dart implementation of layered graph layout. It provides an
elkjs-style graph model and supports compound graphs, ports, configurable
spacing, model-order constraints, and orthogonal edge routing.</p>
<p>The implementation follows the same algorithm family as Eclipse Layout Kernel
and elkjs, but it is not a translation of either project and does not promise
identical coordinates.</p>
<h2 id="use">Use</h2>
<pre><code class="language-dart">import 'package:elk/elk.dart';

void main() {
  final result = const ElkLayered().layout(
    ElkGraph(
      layoutOptions: const ElkLayoutOptions(direction: ElkDirection.down),
      children: [
        ElkNode(id: 'a', width: 80, height: 40),
        ElkNode(id: 'b', width: 80, height: 40),
        ElkNode(id: 'c', width: 80, height: 40),
      ],
      edges: [
        ElkEdge(id: 'e1', sources: ['a'], targets: ['b']),
        ElkEdge(id: 'e2', sources: ['a'], targets: ['c']),
      ],
    ),
  );

  for (final node in result.children) {
    print('${node.id}: ${node.x}, ${node.y}');
  }
}
</code></pre>
<p>Node coordinates are relative to their parent. Use <code>result.nodesById</code> for a
flat map with absolute coordinates.</p>
<h2 id="options">Options</h2>
<p><code>ElkLayoutOptions</code> controls direction, spacing, node placement, fixed
alignment, hierarchy handling, model-order handling, edge merging, and cycle breaking. For
example:</p>
<pre><code class="language-dart">const options = ElkLayoutOptions(
  direction: ElkDirection.right,
  spacingBaseValue: 24,
  forceNodeModelOrder: true,
);
</code></pre>
<p>Edges can refer to a node ID or to an <code>ElkPort</code> ID. A node with children is
laid out as a compound node. Existing elkjs graph JSON can be loaded with
<code>ElkGraph.fromJson</code>.</p>
<h2 id="hierarchy-modes">Hierarchy modes</h2>
<p>Set <code>hierarchyHandling</code> on root or compound <code>ElkLayoutOptions</code>. JSON accepts
<code>org.eclipse.elk.hierarchyHandling</code>, <code>elk.hierarchyHandling</code>, and
<code>hierarchyHandling</code>.</p>
<table>
<thead>
<tr>
<th>Mode</th>
<th>Behavior</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>includeChildren</code> / <code>INCLUDE_CHILDREN</code></td>
<td>Routes edges across included compound boundaries.</td>
</tr>
<tr>
<td><code>separateChildren</code> / <code>SEPARATE_CHILDREN</code></td>
<td>Lays out groups independently. Edges internal to each group, including links from its own boundary ports to its children, remain routed; edges crossing a separated boundary remain in the result with empty <code>sections</code>.</td>
</tr>
<tr>
<td><code>inherit</code> / <code>INHERIT</code></td>
<td>Uses the enclosing mode; at the root, resolves to <code>SEPARATE_CHILDREN</code>.</td>
</tr>
</tbody>
</table>
<p>Omitting the root mode preserves Dart's existing <code>INCLUDE_CHILDREN</code> default.
Omitting a compound override inherits its enclosing mode. An explicit included
child does not reconnect a boundary separated by an ancestor. A direction-only
compound override changes direction without changing the inherited mode; a
hierarchy-only override preserves the inherited direction.</p>
<p>Unlike elkjs 0.9.3, Dart retains cross-boundary edge IDs with empty <code>sections</code>
when an included parent contains a separated child, rather than throwing.
Unrouted edges have no positioned labels. Their original label metadata remains
on the input graph. Consumers should draw only the sections that are present.</p>
<p>Dart also retains its existing mixed-direction support under <code>INCLUDE_CHILDREN</code>.
elkjs 0.9.3 ignores nested directions in that mode. The broader coordinated
hierarchy optimization remains tracked in
<a href="https://github.com/orestesgaolin/mermaid/issues/78">issue #78</a>; these modes do
not promise identical coordinates or crossing order.</p>
<h2 id="validation">Validation</h2>
<p>The comparison tool under <code>tool/validation</code> runs the same graph set through
this package and elkjs and writes side-by-side SVG output:</p>
<pre><code class="language-console">$ cd tool/validation
$ npm install
$ node run_elkjs.mjs
$ cd ../..
$ dart run tool/validation/compare.dart
</code></pre>
<p>The comparison checks layer assignment, node overlap, ordering, and graph
bounds. Differences in within-layer ordering and exact coordinates are
expected.</p>
<p>The hierarchy tests also read retained elkjs 0.9.3 inputs and outputs from
<code>test/fixtures/hierarchy_handling_elkjs.json</code>. After an intentional reference
update, regenerate them from the package root with
<code>node tool/validation/generate_hierarchy_reference.mjs</code>. Ordinary tests never
regenerate reference data.</p>
<h2 id="license">License</h2>
<p>MIT. The package contains a vendored derivative of dart_dagre (Apache-2.0).
See <code>NOTICE</code> and <code>lib/src/dagre/LICENSE</code>.</p>
''';
