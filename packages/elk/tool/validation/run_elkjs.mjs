// Runs the real elkjs over tool/validation/graphs.json and writes the laid-out
// node positions (absolute) to elkjs_out.json, for comparison against our
// Dart port. Usage (from tool/validation/):
//
//   npm install        # installs elkjs (once)
//   node run_elkjs.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import ELK from 'elkjs/lib/elk.bundled.js';

const elk = new ELK();
const cases = JSON.parse(readFileSync(new URL('./graphs.json', import.meta.url)));

// Flatten elkjs's nested result (child x/y are parent-relative) to absolute
// node rects keyed by id, and edge polylines to absolute point arrays. An
// edge's coordinates are relative to the node whose `edges` array holds it
// (its container), so we offset by that node's absolute origin.
function flatten(node, dx, dy, nodes, edges) {
  for (const e of node.edges ?? []) {
    const sec = e.sections?.[0];
    if (!sec) continue;
    const pts = [sec.startPoint, ...(sec.bendPoints ?? []), sec.endPoint]
      .map((p) => ({ x: p.x + dx, y: p.y + dy }));
    edges.push(pts);
  }
  for (const c of node.children ?? []) {
    const x = (c.x ?? 0) + dx;
    const y = (c.y ?? 0) + dy;
    nodes[c.id] = { x, y, width: c.width ?? 0, height: c.height ?? 0 };
    flatten(c, x, y, nodes, edges);
  }
}

const result = {};
for (const { name, graph } of cases) {
  const laid = await elk.layout(structuredClone(graph));
  const nodes = {};
  const edges = [];
  flatten(laid, 0, 0, nodes, edges);
  result[name] = { nodes, edges };
}

// Written as a committed golden so the Dart comparison test runs without Node.
writeFileSync(new URL('./elkjs_golden.json', import.meta.url),
  JSON.stringify(result, null, 2));
console.log(`Wrote elkjs_golden.json for ${Object.keys(result).length} graphs ` +
  `via real elkjs (elk.bundled.js).`);
