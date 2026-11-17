import { APP_CHECK, type AppCheckMode, type Platform } from './config';

/** What the callable framework found: a verified app id, a rejected token, or none. */
export type AppCheckVerdict = 'valid' | 'invalid' | 'missing';

export interface AppCheckInput {
  /** `request.app.appId`, set by the framework only for a verified token. */
  verifiedAppId?: string;
  /** Whether the call carried an X-Firebase-AppCheck header at all. */
  tokenPresent: boolean;
  /** The platform the client declares; it proves nothing (T-19 Design). */
  declaredPlatform: unknown;
  /**
   * True for an anonymous caller (the portfolio demo, T-18): anyone can make
   * such an account, so only a verified token from a configured app lets it
   * through, whatever platform it declares; "monitor" never applies to it.
   */
  requireToken?: boolean;
}

export interface AppCheckDecision {
  allow: boolean;
  verdict: AppCheckVerdict;
  platform: Platform | 'unknown';
  mode: AppCheckMode;
}

/**
 * The function's own App Check rule (Q-34 1; framework enforcement is off).
 * A verified token names its app, and that app's setting applies. Without a
 * verified token only the declared platform is known: a platform on "monitor"
 * lets the call through (the verdict goes to the metadata log), anything else
 * is refused. An unknown platform counts as "enforce". A caller that must
 * show a token (`requireToken`, an anonymous account) is refused without one
 * whatever it declares; the verified app must still be a configured one.
 */
export function decideAppCheck(
  input: AppCheckInput,
  apps: typeof APP_CHECK = APP_CHECK,
): AppCheckDecision {
  if (input.verifiedAppId !== undefined) {
    const platform = platformOfApp(input.verifiedAppId, apps);
    if (platform === undefined) {
      return { allow: false, verdict: 'valid', platform: 'unknown', mode: 'enforce' };
    }
    return { allow: true, verdict: 'valid', platform, mode: apps[platform].mode };
  }
  const verdict: AppCheckVerdict = input.tokenPresent ? 'invalid' : 'missing';
  const declared = input.declaredPlatform;
  if (input.requireToken === true) {
    const platform = declared === 'web' || declared === 'android' ? declared : 'unknown';
    return { allow: false, verdict, platform, mode: 'enforce' };
  }
  if (declared !== 'web' && declared !== 'android') {
    return { allow: false, verdict, platform: 'unknown', mode: 'enforce' };
  }
  const mode = apps[declared].mode;
  return { allow: mode === 'monitor', verdict, platform: declared, mode };
}

function platformOfApp(appId: string, apps: typeof APP_CHECK): Platform | undefined {
  return (Object.keys(apps) as Platform[]).find((platform) => apps[platform].appId === appId);
}
