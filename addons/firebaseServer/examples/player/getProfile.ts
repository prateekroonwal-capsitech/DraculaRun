/**
 * getProfile — HTTPS callable: returns the authenticated player's profile.
 *
 * Auth: Firebase ID token required (verified by Firebase automatically for onCall).
 * Request:  { gameId: string }
 * Response: PlayerProfile
 */

import * as functions from 'firebase-functions/v2';
import { TYPES, IPlayerService } from '@studio/core';
import { logger } from '@studio/shared';
import { GameServiceFactory as factory } from '../di/functions.container';

export const getProfile = functions.https.onCall(
  { maxInstances: 100 },
  async (request) => {
    // For callable functions, auth is automatically verified by Firebase SDK
    if (!request.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Authentication required'
      );
    }

    const { uid } = request.auth;
    const { gameId } = request.data as { gameId: string };

    if (!gameId) {
      throw new functions.https.HttpsError('invalid-argument', 'gameId is required');
    }

    try {
      const playerService = await factory.getService<IPlayerService>(
        gameId,
        TYPES.Services.Player
      );

      const profile = await playerService.getProfile(uid);

      if (!profile) {
        throw new functions.https.HttpsError('not-found', 'Player profile not found');
      }

      if (profile.isBanned) {
        throw new functions.https.HttpsError(
          'permission-denied',
          `Account banned: ${profile.bannedReason ?? 'policy violation'}`
        );
      }

      return profile;
    } catch (err) {
      if (err instanceof functions.https.HttpsError) throw err;
      logger.error('getProfile failed', err, { uid, gameId });
      throw new functions.https.HttpsError('internal', 'Failed to fetch profile');
    }
  }
);
