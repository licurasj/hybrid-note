// The per-app App Check rule (Q-34 1) with a stubbed verifier: the verdict the
// framework would hand over is given directly.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { decideAppCheck } from '../src/appCheck';
import { APP_CHECK } from '../src/config';

const WEB = APP_CHECK.web.appId;
const ANDROID = APP_CHECK.android.appId;

describe('App Check with the shipped settings (web enforce, Android monitor)', () => {
  test('a verified web token passes', () => {
    const d = decideAppCheck({ verifiedAppId: WEB, tokenPresent: true, declaredPlatform: 'web' });
    assert.deepEqual(d, { allow: true, verdict: 'valid', platform: 'web', mode: 'enforce' });
  });

  test('web without a token, or with an invalid one, is refused', () => {
    assert.equal(decideAppCheck({ tokenPresent: false, declaredPlatform: 'web' }).allow, false);
    const invalid = decideAppCheck({ tokenPresent: true, declaredPlatform: 'web' });
    assert.equal(invalid.allow, false);
    assert.equal(invalid.verdict, 'invalid');
  });

  test('Android on monitor passes without a valid token and reports the verdict', () => {
    assert.deepEqual(decideAppCheck({ tokenPresent: false, declaredPlatform: 'android' }), {
      allow: true,
      verdict: 'missing',
      platform: 'android',
      mode: 'monitor',
    });
    assert.equal(decideAppCheck({ tokenPresent: true, declaredPlatform: 'android' }).verdict, 'invalid');
  });

  test('a verified token decides by its app, whatever platform is declared', () => {
    const d = decideAppCheck({ verifiedAppId: ANDROID, tokenPresent: true, declaredPlatform: 'web' });
    assert.equal(d.platform, 'android');
    assert.equal(d.allow, true);
  });

  test('a verified token of an unknown app is refused', () => {
    const d = decideAppCheck({ verifiedAppId: '1:9:web:other', tokenPresent: true, declaredPlatform: 'web' });
    assert.equal(d.allow, false);
  });

  test('an unknown or missing platform without a token counts as enforce', () => {
    for (const declaredPlatform of [undefined, 'ios', 42]) {
      const d = decideAppCheck({ tokenPresent: false, declaredPlatform });
      assert.equal(d.allow, false);
      assert.equal(d.mode, 'enforce');
    }
  });
});

describe('turning Android to enforce is a settings change only', () => {
  const enforced = { ...APP_CHECK, android: { ...APP_CHECK.android, mode: 'enforce' as const } };

  test('Android without a valid token is then refused', () => {
    assert.equal(decideAppCheck({ tokenPresent: false, declaredPlatform: 'android' }, enforced).allow, false);
    assert.equal(decideAppCheck({ tokenPresent: true, declaredPlatform: 'android' }, enforced).allow, false);
  });

  test('a verified Android token still passes', () => {
    const d = decideAppCheck({ verifiedAppId: ANDROID, tokenPresent: true, declaredPlatform: 'android' }, enforced);
    assert.equal(d.allow, true);
  });
});
