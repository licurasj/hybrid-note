// Input checks and limits of the owner tier (Q-29, Q-36).
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { TIERS } from '../src/config';
import { reasonOf } from '../src/errors';
import { parseRequest } from '../src/request';

const limits = TIERS.owner;

function base(extra: Record<string, unknown> = {}) {
  return {
    prompt: 'add milk',
    locale: 'en',
    lists: [{ id: 'grocery', name: 'Grocery', fields: [] }],
    openList: { definition: { id: 'grocery', aiAllowed: true }, items: [] },
    ...extra,
  };
}

function reason(data: unknown) {
  try {
    parseRequest(data, limits);
    return 'accepted';
  } catch (error) {
    return reasonOf(error);
  }
}

describe('parseRequest', () => {
  test('a normal request is accepted', () => {
    assert.equal(reason(base()), 'accepted');
  });

  test('a request with no list open is valid (Q-36)', () => {
    assert.equal(reason(base({ openList: null })), 'accepted');
    const withoutOpen: Record<string, unknown> = base();
    delete withoutOpen.openList;
    assert.equal(reason(withoutOpen), 'accepted');
    assert.equal(parseRequest(withoutOpen, limits).openList, null);
  });

  test('a request with no lists at all is valid', () => {
    assert.equal(reason(base({ lists: [], openList: null })), 'accepted');
  });

  test('the prompt limit counts characters, not UTF-16 units', () => {
    assert.equal(reason(base({ prompt: 'a'.repeat(1000) })), 'accepted');
    assert.equal(reason(base({ prompt: '\u{1F95A}'.repeat(1000) })), 'accepted');
    assert.equal(reason(base({ prompt: 'a'.repeat(1001) })), 'promptTooLong');
  });

  test('context limits: items, lists and bytes', () => {
    const items = Array.from({ length: 21 }, (_, i) => ({ id: `i${i}` }));
    assert.equal(reason(base({ openList: { definition: { id: 'grocery' }, items } })), 'contextTooLarge');
    const lists = Array.from({ length: 101 }, (_, i) => ({ id: `l${i}`, name: 'L', fields: [] }));
    assert.equal(reason(base({ lists, openList: null })), 'contextTooLarge');
    const big = [{ id: 'grocery', name: 'x'.repeat(40000), fields: [] }];
    assert.equal(reason(base({ lists: big })), 'contextTooLarge');
  });

  test('an open list with aiAllowed false is refused', () => {
    const openList = { definition: { id: 'grocery', aiAllowed: false }, items: [] };
    assert.equal(reason(base({ openList })), 'aiNotAllowed');
  });

  test('malformed requests are badRequest', () => {
    for (const data of [
      null,
      'add milk',
      base({ prompt: '' }),
      base({ prompt: '   ' }),
      base({ prompt: 3 }),
      base({ locale: undefined }),
      base({ lists: 'grocery' }),
      base({ lists: [{ id: 'grocery' }] }),
      base({ lists: [{ id: 'a', name: 'A', fields: [] }, { id: 'a', name: 'B', fields: [] }] }),
      base({ openList: { definition: { id: 'elsewhere' }, items: [] } }),
      base({ openList: { definition: { id: 'grocery' }, items: ['text'] } }),
    ]) {
      assert.equal(reason(data), 'badRequest', JSON.stringify(data));
    }
  });
});
