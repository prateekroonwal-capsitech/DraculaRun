/**
 * auth/onDelete — Triggered when a Firebase user account is deleted.
 *
 * Soft-deletes the PlayerProfile (hard-delete violates GDPR 30-day grace).
 * A scheduled function can purge soft-deleted accounts after the grace period.
 */

import * as functions from 'firebase-functions/v2';
import { TYPES, IPlayerService } from '@studio/core';
import { logger } from '@studio/shared';
import { GameServiceFactory as factory } from '../di/functions.container';

export const onUserDeleted = functions.auth.user().onDelete(async (user) => {
  logger.info('User account deleted', { uid: user.uid });

  const STUDIO_GAME_ID = process.env.STUDIO_GAME_ID ?? 'studio';

  try {
    const playerService = await factory.getService<IPlayerService>(
      STUDIO_GAME_ID,
      TYPES.Services.Player
    );

    await playerService.deletePlayer(user.uid);
    logger.info('Player soft-deleted', { uid: user.uid });
  } catch (err) {
    logger.error('Failed to soft-delete player on account deletion', err, {
      uid: user.uid,
    });
  }
});
