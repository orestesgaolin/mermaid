// GENERATED — do not edit. Source: packages/elk/README.md
// Regenerate: dart run tool/gen_readme_html.dart
library;

/// The elk README rendered to HTML (minus its top-level title).
const elkReadmeHtml = r'''
<p>Pure-Dart <strong>layered graph layout</strong> (Sugiyama-style), inspired by the
<a href="https://eclipse.dev/elk/">Eclipse Layout Kernel</a> (ELK) and its JavaScript
port <a href="https://github.com/kieler/elkjs">elkjs</a>.</p>
<ul>
<li><strong>Layered algorithm</strong>: cycle breaking → network-simplex layering → crossing
minimization → Brandes–Köpf coordinate assignment.</li>
<li><strong>Orthogonal edge routing</strong> with computed bend points — the characteristic
ELK look.</li>
<li><strong>Compound graphs / clusters</strong>: nodes can contain children; clusters are
sized and positioned, children returned with parent-relative coordinates.</li>
<li><strong>Ports</strong>: edges can attach at fixed points on node borders.</li>
<li><strong>ELK spacing model</strong> (<code>spacing.baseValue</code>), <strong>model order</strong> crossing
constraints, and Brandes–Köpf fixed-alignment options.</li>
<li><strong>elkjs-style API</strong>, including <code>ElkGraph.fromJson</code> for the elkjs graph JSON —
a recognizable, near-drop-in alternative.</li>
<li><strong>Synchronous, dependency-free, no I/O</strong> — runs in the VM, AOT, Flutter
(mobile/desktop/web) and the browser alike.</li>
</ul>
<blockquote>
<p>Not a transpile of elkjs (which is GWT-compiled Java) — it's a readable Dart
implementation of the same layered algorithm family, so output is <em>ELK-like</em>
but not byte-identical to elkjs. See <a href="#validating-against-elkjs">Validation</a>.</p>
</blockquote>
<h2 id="quick-start">Quick start</h2>
<pre><code class="language-dart">import 'package:elk/elk.dart';

void main() {
  final result = const ElkLayered().layout(ElkGraph(
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
  ));

  for (final node in result.children) {
    print('${node.id}: x=${node.x}, y=${node.y}, ${node.width}x${node.height}');
  }
  for (final edge in result.edges) {
    print('${edge.id}: ${edge.sections.first.points}'); // start, bends…, end
  }
}
</code></pre>
<p>Coordinates: a node's <code>x</code>/<code>y</code> is its top-left <strong>relative to its parent</strong>. Use
<code>result.nodesById</code> for a flat map with <strong>absolute</strong> coordinates.</p>
<h2 id="configuration">Configuration</h2>
<p>All options live on [<code>ElkLayoutOptions</code>]. Defaults match ELK/elkjs for the
<code>layered</code> algorithm as configured by mermaid.</p>
<table>
<thead>
<tr>
<th>Option</th>
<th>Type / values</th>
<th>Default</th>
<th>Effect</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>direction</code></td>
<td><code>down</code>, <code>up</code>, <code>right</code>, <code>left</code></td>
<td><code>down</code></td>
<td>Primary flow direction (the layering axis).</td>
</tr>
<tr>
<td><code>spacingBaseValue</code></td>
<td><code>double</code></td>
<td><code>40</code></td>
<td>Base unit; node/edge/layer gaps are derived from it unless set explicitly.</td>
</tr>
<tr>
<td><code>spacingNodeNode</code></td>
<td><code>double?</code></td>
<td>from base</td>
<td>Gap between adjacent nodes in a layer.</td>
</tr>
<tr>
<td><code>spacingEdgeNode</code></td>
<td><code>double?</code></td>
<td>base × 0.5</td>
<td>Gap between a node and an edge routed past it.</td>
</tr>
<tr>
<td><code>spacingNodeNodeBetweenLayers</code></td>
<td><code>double?</code></td>
<td>from base</td>
<td>Gap between layers.</td>
</tr>
<tr>
<td><code>nodePlacement</code></td>
<td><code>brandesKoepf</code>, …</td>
<td><code>brandesKoepf</code></td>
<td>Coordinate-assignment strategy (others currently fall back to BK).</td>
</tr>
<tr>
<td><code>fixedAlignment</code></td>
<td><code>none</code>, <code>leftUp</code>, <code>leftDown</code>, <code>rightUp</code>, <code>rightDown</code>, <code>balanced</code></td>
<td><code>none</code></td>
<td>Brandes–Köpf alignment; <code>none</code> balances all four (most stable).</td>
</tr>
<tr>
<td><code>considerModelOrder</code></td>
<td><code>none</code>, <code>nodesAndEdges</code>, <code>preferEdges</code>, <code>preferNodes</code></td>
<td><code>none</code></td>
<td>Constrain crossing-min to the input order.</td>
</tr>
<tr>
<td><code>forceNodeModelOrder</code></td>
<td><code>bool</code></td>
<td><code>false</code></td>
<td>Keep siblings strictly in declaration order.</td>
</tr>
<tr>
<td><code>mergeEdges</code></td>
<td><code>bool</code></td>
<td><code>false</code></td>
<td>Merge parallel edges into a shared trunk.</td>
</tr>
<tr>
<td><code>cycleBreaking</code></td>
<td><code>greedy</code>, …</td>
<td><code>greedy</code></td>
<td>Strategy used to break cycles before layering.</td>
</tr>
</tbody>
</table>
<h3 id="direction">Direction</h3>
<pre><code class="language-dart">// Flow left-to-right instead of top-down (e.g. a dependency graph).
const ElkLayoutOptions(direction: ElkDirection.right);
</code></pre>
<h3 id="spacing">Spacing</h3>
<pre><code class="language-dart">// Tighter than the default 40; or set concrete gaps.
const ElkLayoutOptions(spacingBaseValue: 24);
const ElkLayoutOptions(spacingNodeNode: 60, spacingNodeNodeBetweenLayers: 80);
</code></pre>
<h3 id="model-order">Model order</h3>
<p>Keep sibling nodes in the order you declared them (otherwise crossing
minimization is free to reorder them):</p>
<pre><code class="language-dart">const ElkLayoutOptions(forceNodeModelOrder: true);
</code></pre>
<h3 id="ports">Ports</h3>
<p>Give a node <code>ports</code> and reference a port id (instead of the node id) in an
edge's <code>sources</code>/<code>targets</code>. Each port is placed on the node border — its
<code>side</code> is explicit or inferred from the flow direction and whether the port is
used as a source (outgoing side) or target (incoming side) — and ports on a
side are ordered to reduce crossings.</p>
<pre><code class="language-dart">final result = const ElkLayered().layout(ElkGraph(
  layoutOptions: const ElkLayoutOptions(direction: ElkDirection.right),
  children: [
    ElkNode(id: 'hub', width: 80, height: 80, ports: [
      ElkPort(id: 'out1'),
      ElkPort(id: 'out2', side: ElkPortSide.east),
    ]),
    ElkNode(id: 'a', width: 80, height: 40),
    ElkNode(id: 'b', width: 80, height: 40),
  ],
  edges: [
    ElkEdge(id: 'e1', sources: ['out1'], targets: ['a']),
    ElkEdge(id: 'e2', sources: ['out2'], targets: ['b']),
  ],
));
// result.nodesById['hub']!.ports gives each port's position on the border;
// each edge's section starts exactly at its port.
</code></pre>
<h3 id="compound-graphs-clusters">Compound graphs (clusters)</h3>
<p>A node with <code>children</code> becomes a cluster whose size and position are computed:</p>
<pre><code class="language-dart">final result = const ElkLayered().layout(ElkGraph(
  children: [
    ElkNode(id: 'cluster', children: [
      ElkNode(id: 'c1', width: 80, height: 40),
      ElkNode(id: 'c2', width: 80, height: 40),
    ]),
  ],
  edges: [ElkEdge(id: 'e1', sources: ['c1'], targets: ['c2'])],
));
</code></pre>
<h3 id="loading-elkjs-json">Loading elkjs JSON</h3>
<p>The graph model mirrors the elkjs JSON, so an existing elkjs graph drops in:</p>
<pre><code class="language-dart">final graph = ElkGraph.fromJson(jsonDecode(elkjsGraphJsonString));
final result = const ElkLayered().layout(graph);
</code></pre>
<h2 id="validating-against-elkjs">Validating against elkjs</h2>
<p>Exact coordinates will never match elkjs (different implementations), but the
<em>structure</em> should. <code>tool/validation/</code> runs the same graph set through both
engines and scores agreement:</p>
<pre><code class="language-sh">cd tool/validation
npm install            # installs real elkjs (once)
node run_elkjs.mjs     # lays the graphs out with elkjs → elkjs_out.json
cd ../.. &amp;&amp; dart run tool/validation/compare.dart
</code></pre>
<p><code>compare.dart</code> prints a structural-agreement table <strong>and</strong> writes a
side-by-side SVG per graph (ours | elkjs) to <code>tool/validation/output/</code> for
visual comparison.</p>
<p>On the bundled graph set, <code>elk</code> agrees with elkjs <strong>100% on layer
assignment</strong> (which node lands in which layer along the flow axis) and produces
<strong>zero node overlaps</strong>, with comparable bounding-box aspect ratios. Within-layer
ordering differs (different crossing-minimization heuristics; symmetric graphs
are interchangeable either way) — that's the expected, documented divergence.</p>
<h2 id="license">License</h2>
<p>MIT (see <code>LICENSE</code>). Bundles a vendored copy of
<a href="https://pub.dev/packages/dart_dagre">dart_dagre</a> (Apache-2.0) as the layered
algorithm substrate — see <code>NOTICE</code> and <code>lib/src/dagre/LICENSE</code>.</p>
''';
