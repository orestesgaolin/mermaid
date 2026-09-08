// Explicit oracle regeneration; ordinary tests never run elkjs or overwrite it.
import { readFileSync, writeFileSync } from 'node:fs';
import ELK from './node_modules/elkjs/lib/elk.bundled.js';
import elkPackage from './node_modules/elkjs/package.json' with { type: 'json' };
const path = new URL('../../test/fixtures/hierarchy_handling_elkjs.json', import.meta.url);
const fixture = JSON.parse(readFileSync(path, 'utf8'));
const elk = new ELK();
const clean = (value) => Array.isArray(value) ? value.map(clean)
  : value && typeof value === 'object' ? Object.fromEntries(Object.entries(value)
    .filter(([key]) => key !== '$H').map(([key, item]) => [key, clean(item)])) : value;
const cases = [];
for (const { name, input } of fixture.cases) {
  try {
    cases.push({ name, input, output: clean(await elk.layout(structuredClone(input))) });
  } catch (error) {
    cases.push({ name, input, error: String(error?.message ?? error) });
  }
}
writeFileSync(path, JSON.stringify({ elkjsVersion: elkPackage.version, cases }, null, 2) + '\n');
console.log(`Recorded ${cases.length} hierarchy cases with elkjs ${elkPackage.version}.`);
