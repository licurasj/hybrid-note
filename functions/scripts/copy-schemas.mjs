// Copies the AI tool JSON Schemas from the app's schema/ folder into lib/schema/,
// where the function reads them at run time.
//
// T-19 unit 1 owns schema/ and writes the ai_*.schema.json files on
// feat/core-ai-contract; T-19 unit 3 merges that branch and wires the copied
// files into the tool-call check (src/output.ts). Until then this step copies
// whatever ai_* files exist (none on main) and the check is structural only.
import { copyFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', '..', 'schema');
const target = join(here, '..', 'lib', 'schema');

mkdirSync(target, { recursive: true });
const files = existsSync(source)
  ? readdirSync(source).filter((name) => /^ai_.*\.schema\.json$/.test(name))
  : [];
for (const name of files) {
  copyFileSync(join(source, name), join(target, name));
}
console.log(`copy-schemas: ${files.length} AI schema file(s) copied to lib/schema/`);
