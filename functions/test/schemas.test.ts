// The unit 1 tool schemas as the function loads and checks them (T-19 unit 3).
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { TOOL_NAMES } from '../src/provider/types';
import { loadExamples, loadTools, schemaErrors } from '../src/schemas';

const value = (field: string, v: unknown) => ({ field, value: v });

describe('tool schemas', () => {
  test('tools load in TOOL_NAMES order, strict only where named', () => {
    assert.deepEqual(loadTools().map((t) => t.name), [...TOOL_NAMES]);
    assert.ok(loadTools().every((t) => t.strict === undefined));
    const mixed = loadTools(['reply', 'decline']);
    assert.deepEqual(mixed.map((t) => t.name), [...TOOL_NAMES]);
    assert.deepEqual(mixed.filter((t) => t.strict === true).map((t) => t.name), ['reply', 'decline']);
    assert.ok(loadTools([...TOOL_NAMES]).every((t) => t.strict === true));
  });

  test('every example design is a valid create_list call', () => {
    const examples = loadExamples();
    assert.ok(examples.length >= 8);
    for (const example of examples) {
      assert.deepEqual(schemaErrors('create_list', example.input), [], example.id);
    }
  });

  test('good calls of every tool pass', () => {
    const good: [(typeof TOOL_NAMES)[number], unknown][] = [
      ['upsert_items', { listId: 'g', items: [{ values: [value('title', 'eggs'), value('qty', 2)] }, { id: 'i1', values: [value('done', true)] }] }],
      ['delete_items', { listId: 'g', ids: ['i1'] }],
      ['delete_items', { listId: 'g', match: ['milk'] }],
      ['upsert_items', { listId: 'g', items: [{ match: 'milk', values: [] }] }],
      ['patch_list', { listId: 'g', ops: [{ op: 'removeField', key: 'qty' }] }],
      ['choose_list', { question: 'Grocery or Tasks?', candidates: ['g', 't'] }],
      ['reply', { text: 'You have 3 items.' }],
      ['decline', { reason: 'offTopic' }],
    ];
    for (const [name, args] of good) assert.deepEqual(schemaErrors(name, args), [], name);
  });

  test('bad calls fail with path: message lines', () => {
    const bad: [(typeof TOOL_NAMES)[number], unknown][] = [
      ['upsert_items', { listId: 'g', items: [{ values: { title: 'eggs' } }] }], // values as a map
      ['upsert_items', { listId: 'g', items: [] }], // minItems
      ['upsert_items', { listId: 'g', items: [{ values: [value('1bad', 'x')] }] }], // key pattern
      ['delete_items', { listId: 'g', match: [] }], // minItems (ids or match: output.ts, Q-39)
      ['choose_list', { question: 'Which?', candidates: [] }], // minItems 1 (2 without newList: output.ts, Q-43)
      ['reply', { text: 'x'.repeat(501) }], // maxLength
      ['decline', { reason: 'bored' }], // enum
      ['create_list', { list: { name: 'x' }, extra: 1 }], // unknown key
    ];
    for (const [name, args] of bad) {
      const errors = schemaErrors(name, args);
      assert.ok(errors.length > 0 && errors.length <= 10, `${name} ${JSON.stringify(args)}`);
      assert.ok(errors.every((e) => /: /.test(e)));
    }
  });

  test('arguments that were not JSON fail', () => {
    assert.deepEqual(schemaErrors('reply', undefined), ['the arguments are not valid JSON']);
  });
});
