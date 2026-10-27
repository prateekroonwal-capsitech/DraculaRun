/**
 * auth/onCreate — Triggered when a new Firebase user is created.
 *
 * For EVERY new user (iOS, Android, or Guest):
 *  1. Create their PlayerProfile in Firestore
 *  2. Set initial custom claims (role: 'player')
 *  3. Log the event
 *
 * This is the ONLY place PlayerProfile creation happens — clients never
 * write directly to the players collection.
 */

import * as functions from 'firebase-functions/v2';
import { GameServiceFactory, TYPES, IPlayerService, IAuthService } from '@studio/core';
import { logger } from '@studio/shared';
import { GameServiceFactory as factory } from '../di/functions.container';

export const onUserCreated = functions.auth.user().onCreate(async (user) => {
  logger.info('New user created', { uid: user.uid, provider: user.providerData?.[0]?.providerId });

  // For studio-level auth hooks, we use a shared 'studio' gameId
  // Each game's progress is stored under /players/{uid}/progress/{gameId}
  const STUDIO_GAME_ID = process.env.STUDIO_GAME_ID ?? 'studio';

  try {
    const playerService = await factory.getService<IPlayerService>(
      STUDIO_GAME_ID,
      TYPES.Services.Player
    );

    const authService = await factory.getService<IAuthService>(
      STUDIO_GAME_ID,
      TYPES.Services.Auth
    );

    // Create the base profile
    await playerService.createProfile(user.uid, {
      uid: user.uid,
      displayName: user.displayName ?? `Player_${user.uid.slice(0, 6)}`,
      email: user.email,
      avatarUrl: user.photoURL ?? undefined,
      isAnonymous: user.providerData.length === 0,
      platform: 'android', // Will be corrected on first app session
    });

    // Set initial custom claims
    await authService.setCustomClaims(user.uid, {
      role: 'player',
      createdAt: new Date().toISOString(),
    });

    logger.info('Player profile created', { uid: user.uid });
  } catch (err) {
    // Auth onCreate errors don't prevent user creation — log and alert
    logger.critical('Failed to create player profile on user creation', err, {
      uid: user.uid,
    });
  }
});
