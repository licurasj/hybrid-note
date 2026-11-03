// Copies the AI tool definitions and example designs from the app's schema/
// folder into lib/schema/, where the function reads them at run time
// (src/schemas.ts). T-19 unit 1 owns schema/ and generates these files from
// ai_tools.schema.json and list_definition.schema.json, which are sources and
// are not sent. A missing file fails the build, so no function is built or
// deployed without its tool schemas.
import { copyFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const FILES = ['ai_tools.bundle.json', 'ai_tools.strict.json', 'ai_examples.json'];

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', '..', 'schema');
const target = join(here, '..', 'lib', 'schema');

const missing = FILES.filter((name) => !existsSync(join(source, name)));
if (missing.length > 0) {
  console.error(`copy-schemas: missing in schema/: ${missing.join(', ')}`);
  process.exit(1);
}
mkdirSync(target, { recursive: true });
for (const name of FILES) {
  copyFileSync(join(source, name), join(target, name));
}
console.log(`copy-schemas: ${FILES.length} AI schema files copied to lib/schema/`);
