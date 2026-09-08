import { readFileSync, writeFileSync } from 'node:fs';
import ELK from '../../../packages/elk/tool/validation/node_modules/elkjs/lib/elk.bundled.js';
import elkPackage from '../../../packages/elk/tool/validation/node_modules/elkjs/package.json' with { type: 'json' };

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error('usage: node generate_elk_reference.mjs INPUT OUTPUT');
}

const elk = new ELK();
const inputs = JSON.parse(readFileSync(inputPath, 'utf8'));
const knownOptionIds = new Set(
  (await elk.knownLayoutOptions()).flatMap(({ id }) => [
    id,
    id.startsWith('org.eclipse.elk.')
      ? `elk.${id.slice('org.eclipse.elk.'.length)}`
      : id,
  ]),
);

function validateLayoutOptions(element, path) {
  if (element == null || typeof element !== 'object') return;
  const options = element.layoutOptions;
  if (options != null) {
    if (typeof options !== 'object' || Array.isArray(options)) {
      throw new Error(`${path}.layoutOptions must be an object`);
    }
    for (const key of Object.keys(options)) {
      if (!knownOptionIds.has(key)) {
        throw new Error(`Unknown elkjs layout option "${key}" at ${path}.layoutOptions`);
      }
    }
  }
  for (const collection of ['children', 'ports', 'edges', 'labels']) {
    const values = element[collection];
    if (values == null) continue;
    if (!Array.isArray(values)) {
      throw new Error(`${path}.${collection} must be an array`);
    }
    values.forEach((value, index) =>
      validateLayoutOptions(value, `${path}.${collection}[${index}]`),
    );
  }
}

inputs.forEach((entry, index) =>
  validateLayoutOptions(entry.input, `inputs[${index}].input`),
);
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
