// The T-19 unit 3 eval (Q-28): runs every case of cases.ts through the same
// provider step as aiCommand (runModel: system prompt, tool schemas, one
// schema self-correction, output filter) on each named model, and writes the
// owner's grading sheet with measured tokens, cost and latency per request.
//
//   npm run eval -- --dry                         fake provider, no keys, no cost
//   npm run eval -- --providers claude-haiku-5-5,deepseek-flash
//                                                 prints the estimate and stops
//   npm run eval -- --providers ... --yes         real calls (the owner's yes)
//
// Real calls read ANTHROPIC_API_KEY / DEEPSEEK_API_KEY from the git-ignored
// functions/.secret.local that the owner fills in. Keys are never printed,
// logged or written to the results.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { MODELS, TIERS, costMicros, type ModelConfig, type Usage } from '../src/config';
import { runModel } from '../src/handler';
import { filterOutput, type ToolCall } from '../src/output';
import { ClaudeProvider } from '../src/provider/claude';
import { DeepSeekProvider } from '../src/provider/deepseek';
import { FakeProvider } from '../src/provider/fake';
import { ProviderError, type AiProvider } from '../src/provider/types';
import { parseRequest } from '../src/request';
import { schemaErrors } from '../src/schemas';
import { CASES, type EvalCase } from './cases';

const ROOT = join(__dirname, '..', '..'); // functions/
const limits = TIERS.owner;

export interface CaseResult {
  caseId: string;
  model: string;
  outcome: 'ok' | 'declined' | 'outputTooLong' | 'providerError';
  declineReason?: string;
  providerError?: string;
  toolCalls: ToolCall[];
  droppedText: number;
  droppedTools: number;
  attempts: number;
  stopReason?: string;
  usage: Usage;
  costUsd: number;
  /** The cost if nothing had been cached (sporadic use rarely hits the cache). */
  coldCostUsd: number;
  latencyMs: number;
  autoCheck: string;
}

/** KEY=value lines of .secret.local; values are kept in memory only. */
export function readSecrets(path: string): Record<string, string> {
  if (!existsSync(path)) return {};
  const secrets: Record<string, string> = {};
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const match = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (match && !line.trimStart().startsWith('#')) secrets[match[1]] = match[2].replace(/^(['"])(.*)\1$/, '$2');
  }
  return secrets;
}

function providerFor(model: ModelConfig, secrets: Record<string, string>): AiProvider {
  switch (model.provider) {
    case 'fake':
      return new FakeProvider();
    case 'claude':
      return new ClaudeProvider(secrets.ANTHROPIC_API_KEY);
    case 'deepseek':
      return new DeepSeekProvider(secrets.DEEPSEEK_API_KEY);
  }
}

function coldCost(model: ModelConfig, usage: Usage, at: Date): number {
  const all = usage.inputTokens + usage.cacheReadTokens + usage.cacheWriteTokens;
  return costMicros(model, { inputTokens: all, outputTokens: usage.outputTokens, cacheReadTokens: 0, cacheWriteTokens: 0 }, at) / 1e6;
}

export async function runCase(testCase: EvalCase, model: ModelConfig, provider: AiProvider): Promise<CaseResult> {
  const request = parseRequest(testCase.data, limits);
  const started = new Date();
  const base = { caseId: testCase.id, model: model.model, droppedText: 0, droppedTools: 0, toolCalls: [] as ToolCall[] };
  try {
    const { response, usage, attempts } = await runModel(provider, model, request, schemaErrors, started);
    const latencyMs = Date.now() - started.getTime();
    const costs = { usage, costUsd: costMicros(model, usage, started) / 1e6, coldCostUsd: coldCost(model, usage, started) };
    if (response.stopReason === 'length') {
      return { ...base, ...costs, outcome: 'outputTooLong', attempts, stopReason: 'length', latencyMs, autoCheck: 'cut at the length limit' };
    }
    const output = filterOutput(response, request, limits, schemaErrors);
    return {
      ...base,
      ...costs,
      outcome: output.outcome,
      ...(output.declineReason ? { declineReason: output.declineReason } : {}),
      toolCalls: output.toolCalls,
      droppedText: output.droppedText,
      droppedTools: output.droppedTools,
      attempts,
      stopReason: response.stopReason,
      latencyMs,
      autoCheck: testCase.check(output.toolCalls, output.declineReason) ?? 'pass',
    };
  } catch (error) {
    const kind = error instanceof ProviderError ? error.kind : 'unknown';
    return {
      ...base,
      outcome: 'providerError',
      providerError: kind,
      attempts: 0,
      usage: { inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 },
      costUsd: 0,
      coldCostUsd: 0,
      latencyMs: Date.now() - started.getTime(),
      autoCheck: `provider error ${kind}`,
    };
  }
}

const usd = (n: number) => `$${n.toFixed(5)}`;

/** The grading sheet: per case the prompt, the rubric and each model's answer with blank grades. */
export function gradingSheet(results: CaseResult[], models: string[], when: string): string {
  const lines: string[] = [
    `# T-19 unit 3 eval: grading sheet`,
    '',
    `Run ${when}. Models: ${models.join(', ')}. ${CASES.length} cases. Grade each answer 1-5 (5 = exactly what you wanted)`,
    'and write a note where it matters. The auto check only tests the kind of answer and the target list.',
    '',
    '## Totals',
    '',
    '| Model | Auto checks passed | Requests | Retries | Errors | Total cost | Mean cost / request | Mean cold cost / request | Mean input tokens (uncached + cache read + cache write) | Mean output tokens | Median latency |',
    '|---|---|---|---|---|---|---|---|---|---|---|',
  ];
  for (const model of models) {
    const rs = results.filter((r) => r.model === model);
    const n = rs.length || 1;
    const sum = (f: (r: CaseResult) => number) => rs.reduce((s, r) => s + f(r), 0);
    const latencies = rs.map((r) => r.latencyMs).sort((a, b) => a - b);
    lines.push(
      `| ${model} | ${rs.filter((r) => r.autoCheck === 'pass').length}/${rs.length} | ${rs.length} | ${rs.filter((r) => r.attempts === 2).length} | ` +
        `${rs.filter((r) => r.outcome === 'providerError' || r.outcome === 'outputTooLong').length} | ${usd(sum((r) => r.costUsd))} | ` +
        `${usd(sum((r) => r.costUsd) / n)} | ${usd(sum((r) => r.coldCostUsd) / n)} | ` +
        `${Math.round(sum((r) => r.usage.inputTokens) / n)} + ${Math.round(sum((r) => r.usage.cacheReadTokens) / n)} + ${Math.round(sum((r) => r.usage.cacheWriteTokens) / n)} | ` +
        `${Math.round(sum((r) => r.usage.outputTokens) / n)} | ${latencies[Math.floor(latencies.length / 2)] ?? 0} ms |`,
    );
  }
  lines.push('', 'Your pick (model and why): ', '');
  for (const testCase of CASES) {
    const open = (testCase.data.openList as { definition: { id: string } } | null)?.definition.id ?? 'none';
    lines.push(
      `## ${testCase.id} (${testCase.category})`,
      '',
      `Prompt: "${testCase.data.prompt}" · open list: ${open} · locale: ${testCase.data.locale}`,
      '',
      `Good answer: ${testCase.rubric}`,
      '',
    );
    for (const model of models) {
      const r = results.find((x) => x.caseId === testCase.id && x.model === model);
      if (r === undefined) continue;
      const head =
        r.outcome === 'declined'
          ? `declined: ${r.declineReason}`
          : r.outcome === 'ok'
            ? `${r.toolCalls.length} tool call(s)`
            : `${r.outcome}${r.providerError ? ` (${r.providerError})` : ''}`;
      lines.push(
        `### ${model}: ${head}`,
        '',
        `Auto check: ${r.autoCheck} · attempts ${r.attempts} · ${r.usage.inputTokens}+${r.usage.cacheReadTokens}+${r.usage.cacheWriteTokens} in / ` +
          `${r.usage.outputTokens} out · ${usd(r.costUsd)} (cold ${usd(r.coldCostUsd)}) · ${r.latencyMs} ms` +
          (r.droppedText || r.droppedTools ? ` · dropped ${r.droppedText} text, ${r.droppedTools} tool` : ''),
        '',
      );
      if (r.toolCalls.length > 0) lines.push('```json', JSON.stringify(r.toolCalls, null, 2), '```', '');
      lines.push('Grade (1-5): ___ Note: ', '');
    }
  }
  return lines.join('\n');
}

function csv(results: CaseResult[]): string {
  const head = 'case,model,outcome,declineReason,autoCheck,attempts,inputTokens,cacheReadTokens,cacheWriteTokens,outputTokens,costUsd,coldCostUsd,latencyMs';
  const rows = results.map((r) =>
    [r.caseId, r.model, r.outcome, r.declineReason ?? '', `"${r.autoCheck.replace(/"/g, "'")}"`, r.attempts, r.usage.inputTokens,
      r.usage.cacheReadTokens, r.usage.cacheWriteTokens, r.usage.outputTokens, r.costUsd.toFixed(6), r.coldCostUsd.toFixed(6), r.latencyMs].join(','),
  );
  return [head, ...rows].join('\n') + '\n';
}

/** Runs every case on each model in turn and writes results.json, results.csv and grading.md. */
export async function runEval(models: string[], secrets: Record<string, string>, outDir: string): Promise<CaseResult[]> {
  const results: CaseResult[] = [];
  for (const name of models) {
    const model = MODELS[name];
    const provider = providerFor(model, secrets);
    for (const testCase of CASES) {
      const result = await runCase(testCase, model, provider);
      results.push(result);
      console.log(`${name} ${testCase.id}: ${result.outcome} ${result.autoCheck} ${usd(result.costUsd)} ${result.latencyMs} ms`);
    }
  }
  mkdirSync(outDir, { recursive: true });
  const when = new Date().toISOString();
  const ids = models.map((name) => MODELS[name].model);
  writeFileSync(join(outDir, 'results.json'), JSON.stringify({ when, models: ids, results }, null, 2));
  writeFileSync(join(outDir, 'results.csv'), csv(results));
  writeFileSync(join(outDir, 'grading.md'), gradingSheet(results, ids, when));
  return results;
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const dry = args.includes('--dry');
  const flag = args.indexOf('--providers');
  const models = dry ? ['fake'] : flag >= 0 ? (args[flag + 1] ?? '').split(',').filter(Boolean) : [];
  const unknown = models.filter((m) => !(m in MODELS));
  if (models.length === 0 || unknown.length > 0) {
    console.error(`usage: --dry | --providers ${Object.keys(MODELS).filter((m) => m !== 'fake').join(',')} [--yes]`);
    process.exit(2);
  }
  if (!dry && !args.includes('--yes')) {
    // Upper bound per model: every case at the ceiling of one call.
    for (const name of models) {
      const m = MODELS[name];
      const p = m.peak?.prices ?? m.prices;
      const perCall = (m.maxInputTokens * p.inputUsdPerMTok + m.maxOutputTokens * p.outputUsdPerMTok) / 1e6;
      console.log(`${name}: ${CASES.length} cases, at most about ${usd(perCall * CASES.length * 2)} (every call at its ceiling, every case retried)`);
    }
    console.log('Nothing was sent. Add --yes to make the real calls.');
    return;
  }
  const secrets = dry ? {} : readSecrets(join(ROOT, '.secret.local'));
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outDir = join(ROOT, 'eval', 'results', `${dry ? 'dry-' : ''}${stamp}`);
  await runEval(models, secrets, outDir);
  console.log(`Results in ${outDir}`);
}

if (require.main === module) {
  main().catch((error) => {
    // Error kinds only; provider messages may echo request text.
    console.error(error instanceof ProviderError ? error.message : 'eval failed');
    process.exit(1);
  });
}
