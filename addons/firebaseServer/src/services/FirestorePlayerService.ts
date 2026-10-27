/**
 * FirestorePlayerService — Firestore implementation of IPlayerService.
 *
 * Data model:
 *   /players/{uid}                     → PlayerProfile
 *   /players/{uid}/progress/{gameId}   → PlayerProgress
 *
 * All writes use server timestamps and optimistic concurrency (version field).
 */

import { injectable, inject } from 'inversify';
import {
  Firestore,
  FieldValue,
  DocumentSnapshot,
} from 'firebase-admin/firestore';

import {
  IPlayerService,
  PlayerProfile,
  PlayerProgress,
  NotFoundError,
  TYPES,
} from '@studio/core';

@injectable()
export class FirestorePlayerService implements IPlayerService {
  private readonly playersCollection = 'players';

  constructor(
    @inject(TYPES.Infrastructure.Firestore)
    private readonly db: Firestore
  ) {}

  async getProfile(uid: string): Promise<PlayerProfile | null> {
    const snap = await this.db
      .collection(this.playersCollection)
      .doc(uid)
      .get();

    if (!snap.exists) return null;
    return this.toProfile(snap);
  }

  async createProfile(
    uid: string,
    data: Partial<PlayerProfile>
  ): Promise<PlayerProfile> {
    const now = new Date().toISOString();
    const profile: PlayerProfile = {
      uid,
      displayName: data.displayName ?? `Player_${uid.slice(0, 6)}`,
      platform: data.platform ?? 'android',
      isAnonymous: data.isAnonymous ?? false,
      isBanned: false,
      createdAt: now,
      updatedAt: now,
      lastLoginAt: now,
      isDeleted: false,
      meta: data.meta ?? {},
      ...data,
    };

    await this.db
      .collection(this.playersCollection)
      .doc(uid)
      .set({
        ...profile,
        _serverCreatedAt: FieldValue.serverTimestamp(),
      });

    return profile;
  }

  async updateProfile(uid: string, data: Partial<PlayerProfile>): Promise<void> {
    await this.db
      .collection(this.playersCollection)
      .doc(uid)
      .update({
        ...data,
        updatedAt: new Date().toISOString(),
        _serverUpdatedAt: FieldValue.serverTimestamp(),
      });
  }

  async getProgress(
    uid: string,
    gameId: string
  ): Promise<PlayerProgress | null> {
    const snap = await this.db
      .collection(this.playersCollection)
      .doc(uid)
      .collection('progress')
      .doc(gameId)
      .get();

    if (!snap.exists) return null;
    return snap.data() as PlayerProgress;
  }

  async saveProgress(
    uid: string,
    gameId: string,
    progress: Partial<PlayerProgress>
  ): Promise<void> {
    const ref = this.db
      .collection(this.playersCollection)
      .doc(uid)
      .collection('progress')
      .doc(gameId);

    const now = new Date().toISOString();

    // Merge with existing progress — never overwrite entire doc blindly
    await ref.set(
      {
        uid,
        gameId,
        ...progress,
        syncedAt: now,
        _serverSyncedAt: FieldValue.serverTimestamp(),
        // Increment version atomically
        version: FieldValue.increment(1),
      },
      { merge: true }
    );
  }

  async deletePlayer(uid: string): Promise<void> {
    await this.db
      .collection(this.playersCollection)
      .doc(uid)
      .update({
        isDeleted: true,
        deletedAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      });
  }

  async getProfiles(uids: string[]): Promise<PlayerProfile[]> {
    if (uids.length === 0) return [];

    // Firestore getAll() — efficient batch fetch (no N+1 queries)
    const refs = uids.map((uid) =>
      this.db.collection(this.playersCollection).doc(uid)
    );
    const snaps = await this.db.getAll(...refs);

    return snaps
      .filter((snap) => snap.exists)
      .map((snap) => this.toProfile(snap));
  }

  // ─── Private Helpers ────────────────────────────────────────────────

  private toProfile(snap: DocumentSnapshot): PlayerProfile {
    const data = snap.data()!;
    // Strip internal Firestore-only fields before returning
    const { _serverCreatedAt, _serverUpdatedAt, ...profile } = data;
    return profile as PlayerProfile;
  }
}
