// Copies the AI tool definitions from the app's schema/ folder into lib/schema/,
// where the function reads them at run time.
//
// T-19 unit 1 owns schema/ and generates these files on feat/core-ai-contract
// (ai_tools.schema.json and list_definition.schema.json are their sources and
// are not sent). T-19 unit 3 merges that branch and wires the copied files
// into the tool-call check (src/output.ts). Until then none exist on this
// branch, nothing is copied and the check is structural only.
import { copyFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const FILES = ['ai_tools.bundle.json', 'ai_tools.strict.json', 'ai_examples.json'];

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', '..', 'schema');
const target = join(here, '..', 'lib', 'schema');

mkdirSync(target, { recursive: true });
const present = FILES.filter((name) => existsSync(join(source, name)));
for (const name of present) {
  copyFileSync(join(source, name), join(target, name));
}
console.log(`copy-schemas: ${present.length} of ${FILES.length} AI schema files copied to lib/schema/`);
