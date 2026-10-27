/**
 * firebase.module.ts — Inversify ContainerModule for all Firebase bindings.
 *
 * Load this module into any game container to get Firebase-backed services.
 * The module reads env vars for Firebase config — no hardcoded credentials.
 *
 * Usage:
 *   container.load(firebaseModule);
 */

import { ContainerModule } from 'inversify';
import { initializeApp, getApps, cert, App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getRemoteConfig } from 'firebase-admin/remote-config';
import { getStorage } from 'firebase-admin/storage';

import {
  TYPES,
  IAuthService,
  IPlayerService,
  IRemoteConfigService,
  IStorageService,
} from '@studio/core';

import { FirebaseAuthService } from '../services/FirebaseAuthService';
import { FirestorePlayerService } from '../services/FirestorePlayerService';
import { FirebaseRemoteConfigService } from '../services/FirebaseRemoteConfigService';
import { FirebaseStorageService } from '../services/FirebaseStorageService';

function getOrInitFirebaseApp(): App {
  if (getApps().length > 0) return getApps()[0];

  // When running on Cloud Functions / Cloud Run, Application Default Credentials
  // are picked up automatically — no service account key file needed.
  const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (serviceAccountPath) {
    // Local dev: explicit service account JSON
    return initializeApp({
      credential: cert(require(serviceAccountPath)),
      storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
    });
  }

  // Cloud Functions / Cloud Run: ADC
  return initializeApp({
    storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
  });
}

export const firebaseModule = new ContainerModule((bind) => {
  const app = getOrInitFirebaseApp();

  // ─── Infrastructure bindings ─────────────────────────────────────────
  bind<App>(TYPES.Infrastructure.FirebaseApp).toConstantValue(app);

  bind(TYPES.Infrastructure.FirebaseAuth).toConstantValue(getAuth(app));
  bind(TYPES.Infrastructure.Firestore).toConstantValue(getFirestore(app));
  bind(TYPES.Infrastructure.FirebaseRemoteConfig).toConstantValue(
    getRemoteConfig(app)
  );
  bind(TYPES.Infrastructure.FirebaseStorage).toConstantValue(
    getStorage(app).bucket()
  );

  // ─── Service bindings ─────────────────────────────────────────────────
  bind<IAuthService>(TYPES.Services.Auth)
    .to(FirebaseAuthService)
    .inSingletonScope();

  bind<IPlayerService>(TYPES.Services.Player)
    .to(FirestorePlayerService)
    .inSingletonScope();

  bind<IRemoteConfigService>(TYPES.Services.RemoteConfig)
    .to(FirebaseRemoteConfigService)
    .inSingletonScope();

  bind<IStorageService>(TYPES.Services.Storage)
    .to(FirebaseStorageService)
    .inSingletonScope();
});
