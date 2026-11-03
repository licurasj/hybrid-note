import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import Ajv2020, { type ValidateFunction } from 'ajv/dist/2020';

import { TOOL_NAMES, type ToolDef, type ToolName } from './provider/types';

// The AI tool definitions and example designs of T-19 unit 1. They live in the
// app's schema/ folder (Core-owned, generated from ai_tools.schema.json);
// scripts/copy-schemas.mjs copies them to lib/schema/ at build time and fails
// the build when one is missing, so the function always ships with them.
const DIR = join(__dirname, '..', 'schema');

function read<T>(name: string): T {
  return JSON.parse(readFileSync(join(DIR, name), 'utf8')) as T;
}

let full: ToolDef[] | undefined;
let strict: ToolDef[] | undefined;
let validators: Map<string, ValidateFunction> | undefined;

/** The tools as sent: the strict variant for providers whose strict mode accepts it. */
export function loadTools(strictVariant: boolean): ToolDef[] {
  if (strictVariant) return (strict ??= checkNames(read<ToolDef[]>('ai_tools.strict.json')));
  return (full ??= checkNames(read<ToolDef[]>('ai_tools.bundle.json')));
}

export interface Example {
  id: string;
  request: string;
  tool: string;
  input: unknown;
}

export function loadExamples(): Example[] {
  return read<{ examples: Example[] }>('ai_examples.json').examples;
}

function checkNames(tools: ToolDef[]): ToolDef[] {
  const names = tools.map((tool) => tool.name).join(',');
  if (names !== TOOL_NAMES.join(',')) throw new Error(`tool schemas out of step with TOOL_NAMES: ${names}`);
  return tools;
}

/**
 * Checks one tool call against the full schema (with the length, pattern and
 * count limits the strict variant leaves out). Returns the errors, at most 10,
 * as "path: message" lines naming schema rules only, never values.
 */
export function schemaErrors(name: ToolName, args: unknown): string[] {
  if (validators === undefined) {
    const ajv = new Ajv2020({ allErrors: true, strict: false });
    validators = new Map(loadTools(false).map((tool) => [tool.name, ajv.compile(tool.input_schema)]));
  }
  const validate = validators.get(name);
  if (validate === undefined) return [`unknown tool ${name}`];
  if (args === undefined) return ['the arguments are not valid JSON'];
  if (validate(args)) return [];
  return (validate.errors ?? []).slice(0, 10).map((e) => `${e.instancePath || '(arguments)'}: ${e.message ?? e.keyword}`);
}
