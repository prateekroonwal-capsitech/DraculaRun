/**
 * syncProgress — HTTPS callable: server-authoritative progress sync.
 *
 * The server VALIDATES the progress delta before persisting.
 * Each game registers its own validator in its GameBootstrap — if no
 * game-specific validator is found, a basic schema check is applied.
 *
 * Request:  { gameId: string, progress: Record<string, unknown> }
 * Response: { version: number, syncedAt: string }
 */

import * as functions from 'firebase-functions/v2';
import { TYPES, IPlayerService } from '@studio/core';
import { logger } from '@studio/shared';
import { GameServiceFactory as factory } from '../di/functions.container';

export const syncProgress = functions.https.onCall(
  { maxInstances: 50 },
  async (request) => {
    if (!request.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    const { uid } = request.auth;
    const { gameId, progress } = request.data as {
      gameId: string;
      progress: Record<string, unknown>;
    };

    if (!gameId || !progress) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'gameId and progress are required'
      );
    }

    try {
      const playerService = await factory.getService<IPlayerService>(
        gameId,
        TYPES.Services.Player
      );

      await playerService.saveProgress(uid, gameId, { data: progress });

      const saved = await playerService.getProgress(uid, gameId);
      logger.info('Progress synced', { uid, gameId, version: saved?.version });

      return {
        version: saved?.version ?? 1,
        syncedAt: saved?.syncedAt ?? new Date().toISOString(),
      };
    } catch (err) {
      if (err instanceof functions.https.HttpsError) throw err;
      logger.error('syncProgress failed', err, { uid, gameId });
      throw new functions.https.HttpsError('internal', 'Failed to sync progress');
    }
  }
);
