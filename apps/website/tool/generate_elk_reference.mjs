import { readFileSync, writeFileSync } from 'node:fs';
import ELK from '../../../packages/elk/tool/validation/node_modules/elkjs/lib/elk.bundled.js';
import elkPackage from '../../../packages/elk/tool/validation/node_modules/elkjs/package.json' with { type: 'json' };

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error('usage: node generate_elk_reference.mjs INPUT OUTPUT');
}

const elk = new ELK();
const inputs = JSON.parse(readFileSync(inputPath, 'utf8'));
const snapshots = {};
for (const entry of inputs) {
  try {
    snapshots[entry.title] = {
      version: elkPackage.version,
      input: entry.input,
      output: await elk.layout(structuredClone(entry.input)),
    };
  } catch (error) {
    snapshots[entry.title] = {
      version: elkPackage.version,
      input: entry.input,
      error: String(error?.message ?? error),
    };
  }
}
writeFileSync(outputPath, JSON.stringify(snapshots));
console.log(`Generated ${Object.keys(snapshots).length} elkjs ${elkPackage.version} snapshots.`);
