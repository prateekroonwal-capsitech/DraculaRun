/**
 * FirebaseAuthService — Firebase Admin SDK implementation of IAuthService.
 * Works for BOTH iOS and Android (Firebase handles platform auth uniformly).
 *
 * Platform flow:
 *   iOS   → Sign in with Apple or Google → Firebase ID Token → verifyToken()
 *   Android → Google Sign-In → Firebase ID Token → verifyToken()
 *   Guest → Firebase Anonymous Auth → Firebase ID Token → verifyToken()
 */

import { injectable, inject } from 'inversify';
import { Auth, DecodedIdToken } from 'firebase-admin/auth';

import {
  IAuthService,
  AuthVerifyResult,
  AuthError,
  TYPES,
} from '@studio/core';

@injectable()
export class FirebaseAuthService implements IAuthService {
  constructor(
    @inject(TYPES.Infrastructure.FirebaseAuth)
    private readonly auth: Auth
  ) {}

  async verifyToken(idToken: string): Promise<AuthVerifyResult> {
    try {
      const decoded: DecodedIdToken = await this.auth.verifyIdToken(
        idToken,
        true // checkRevoked — ensures revoked tokens are rejected
      );

      const platform = this.resolvePlatform(decoded);

      return {
        uid: decoded.uid,
        email: decoded.email,
        platform,
        isAnonymous: decoded.firebase?.sign_in_provider === 'anonymous',
        claims: this.extractCustomClaims(decoded),
      };
    } catch (err: any) {
      throw new AuthError(
        `Token verification failed: ${err?.message ?? 'unknown error'}`,
        { originalCode: err?.code }
      );
    }
  }

  async createCustomToken(
    uid: string,
    claims?: Record<string, unknown>
  ): Promise<string> {
    try {
      return await this.auth.createCustomToken(uid, claims);
    } catch (err: any) {
      throw new AuthError(`Failed to create custom token: ${err?.message}`, {
        uid,
      });
    }
  }

  async revokeTokens(uid: string): Promise<void> {
    await this.auth.revokeRefreshTokens(uid);
  }

  async deleteUser(uid: string): Promise<void> {
    await this.auth.deleteUser(uid);
  }

  async setCustomClaims(
    uid: string,
    claims: Record<string, unknown>
  ): Promise<void> {
    await this.auth.setCustomUserClaims(uid, claims);
  }

  // ─── Private Helpers ────────────────────────────────────────────────

  private resolvePlatform(
    decoded: DecodedIdToken
  ): 'ios' | 'android' | 'guest' {
    if (decoded.firebase?.sign_in_provider === 'anonymous') return 'guest';

    // Clients should set a custom claim 'platform' on first login
    const claimed = decoded['platform'];
    if (claimed === 'ios' || claimed === 'android') return claimed;

    // Fallback: infer from sign-in provider (imprecise — prefer custom claim)
    const provider = decoded.firebase?.sign_in_provider ?? '';
    if (provider === 'apple.com') return 'ios';

    return 'android'; // Default for Google, email, etc.
  }

  private extractCustomClaims(
    decoded: DecodedIdToken
  ): Record<string, unknown> {
    // Strip standard JWT claims; return only custom ones
    const reserved = new Set([
      'iss', 'aud', 'auth_time', 'user_id', 'sub', 'iat',
      'exp', 'email', 'email_verified', 'phone_number',
      'name', 'picture', 'uid', 'firebase',
    ]);
    return Object.fromEntries(
      Object.entries(decoded).filter(([k]) => !reserved.has(k))
    );
  }
}
