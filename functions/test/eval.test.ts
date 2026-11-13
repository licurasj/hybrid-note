// The eval script's cases and output, run with the fake provider only (no
// keys, no network). The real run is the owner's yes (T-19 unit 3).
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, test } from 'node:test';

import { TIERS } from '../src/config';
import { parseRequest } from '../src/request';
import { CASES } from '../eval/cases';
import { readSecrets, runEval } from '../eval/run';

describe('eval cases', () => {
  test('about 20 cases with unique ids and the planned mix', () => {
    assert.ok(CASES.length >= 20);
    assert.equal(new Set(CASES.map((c) => c.id)).size, CASES.length);
    const count = (category: string) => CASES.filter((c) => c.category === category).length;
    assert.ok(count('items') >= 4);
    assert.ok(count('structure') >= 3);
    assert.ok(count('design') >= 6);
    assert.ok(count('offTopic') >= 4);
    const routing = CASES.filter((c) => c.category === 'routing');
    assert.ok(routing.every((c) => c.data.openList === null), 'routing cases have no list open');
    assert.ok(routing.some((c) => c.data.prompt === 'eggs on Friday'));
    assert.ok(routing.some((c) => c.data.prompt === 'renew passport'));
    assert.ok(routing.filter((c) => c.id.includes('ambiguous')).length >= 2);
  });

  test('the summary of a closed list says its reminder field is required (T-13 unit 14, G7)', () => {
    const c = CASES.find((x) => x.id === 'remind-clear-required-closed');
    assert.ok(c !== undefined);
    assert.equal(c.data.openList, null);
    const parsed = parseRequest(c.data, TIERS.owner);
    const appointments = parsed.lists.find((list) => list.id === 'appointments') as unknown as {
      fields: { key: string; required?: boolean }[];
    };
    assert.equal(appointments.fields.find((f) => f.key === 'reminderAt')?.required, true);
    const tasks = parsed.lists.find((list) => list.id === 'tasks') as unknown as {
      fields: { key: string; required?: boolean }[];
    };
    assert.equal(tasks.fields.find((f) => f.key === 'reminderAt')?.required, undefined);
  });

  test('every case is a request aiCommand accepts under the owner limits', () => {
    for (const c of CASES) assert.doesNotThrow(() => parseRequest(c.data, TIERS.owner), c.id);
  });
});

describe('eval run (fake provider)', () => {
  test('writes results and a grading sheet with every case and the cost columns', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'hn-eval-'));
    try {
      const log = console.log;
      console.log = () => {};
      let results;
      try {
        results = await runEval(['fake'], {}, dir);
      } finally {
        console.log = log;
      }
      assert.equal(results.length, CASES.length);
      assert.ok(results.every((r) => r.outcome !== 'providerError'));
      const sheet = readFileSync(join(dir, 'grading.md'), 'utf8');
      for (const c of CASES) assert.ok(sheet.includes(`## ${c.id} (`), c.id);
      assert.ok(sheet.includes('Mean cost / request'));
      assert.ok(sheet.includes(`| fake-model | `) && !sheet.includes('| 0/0 |'), 'the totals row counts the results');
      assert.ok(sheet.includes('### fake-model: '));
      const csv = readFileSync(join(dir, 'results.csv'), 'utf8').trim().split('\n');
      assert.equal(csv.length, CASES.length + 1);
      const json = JSON.parse(readFileSync(join(dir, 'results.json'), 'utf8'));
      assert.equal(json.results.length, CASES.length);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test('runs only the chosen cases', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'hn-eval-'));
    const log = console.log;
    console.log = () => {};
    try {
      const two = CASES.filter((c) => c.id === 'design-meals' || c.id === 'route-ambiguous-shoes');
      const results = await runEval(['fake'], {}, dir, two);
      assert.deepEqual(results.map((r) => r.caseId), two.map((c) => c.id));
      const sheet = readFileSync(join(dir, 'grading.md'), 'utf8');
      assert.ok(sheet.includes('2 cases') && !sheet.includes('## add-grocery ('));
    } finally {
      console.log = log;
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test('reads KEY=value secrets, skipping comments and quotes', () => {
    const dir = mkdtempSync(join(tmpdir(), 'hn-secret-'));
    try {
      const file = join(dir, '.secret.local');
      writeFileSync(file, '# comment\r\nANTHROPIC_API_KEY="abc"\nDEEPSEEK_API_KEY = def\n');
      assert.deepEqual(readSecrets(file), { ANTHROPIC_API_KEY: 'abc', DEEPSEEK_API_KEY: 'def' });
      assert.deepEqual(readSecrets(join(dir, 'missing')), {});
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
