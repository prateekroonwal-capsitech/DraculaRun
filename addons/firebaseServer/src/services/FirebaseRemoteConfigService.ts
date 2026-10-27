/**
 * FirebaseRemoteConfigService — Remote Config + Version Check implementation.
 *
 * Version check logic:
 *   Remote Config keys (use gameId prefix):
 *     {gameId}_min_version_ios       → "1.2.0"
 *     {gameId}_min_version_android   → "1.2.0"
 *     {gameId}_rec_version_ios       → "1.5.0"
 *     {gameId}_maintenance_mode      → false
 *     {gameId}_maintenance_message   → ""
 *
 * Caching:
 *   Template is fetched once and cached for CACHE_TTL_MS.
 *   Call refresh() to force a reload (live-ops events, etc.)
 */

import { injectable, inject } from 'inversify';
import { RemoteConfig } from 'firebase-admin/remote-config';

import {
  IRemoteConfigService,
  VersionCheckResult,
  RemoteConfigTemplate,
  GameConfig,
  MaintenanceError,
  TYPES,
} from '@studio/core';

const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

function semverCompare(a: string, b: string): number {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] ?? 0) > (pb[i] ?? 0)) return 1;
    if ((pa[i] ?? 0) < (pb[i] ?? 0)) return -1;
  }
  return 0;
}

@injectable()
export class FirebaseRemoteConfigService implements IRemoteConfigService {
  private cachedTemplate: RemoteConfigTemplate | null = null;
  private cacheExpiresAt = 0;

  constructor(
    @inject(TYPES.Infrastructure.FirebaseRemoteConfig)
    private readonly remoteConfig: RemoteConfig,

    @inject(TYPES.Config.Game)
    private readonly gameConfig: GameConfig
  ) {}

  async checkVersion(
    clientVersion: string,
    platform: 'ios' | 'android'
  ): Promise<VersionCheckResult> {
    const prefix = this.gameConfig.remoteConfigPrefix;
    const template = await this.getTemplate(this.gameConfig.gameId);

    const maintenanceMode =
      this.gameConfig.maintenanceMode ??
      (template[`${prefix}_maintenance_mode`] as boolean) ??
      false;

    const maintenanceMessage =
      (template[`${prefix}_maintenance_message`] as string) ?? undefined;

    // Maintenance takes priority over version checks
    if (maintenanceMode) {
      throw new MaintenanceError(maintenanceMessage);
    }

    const platformKey = platform === 'ios' ? 'ios' : 'android';

    const minimumVersion =
      (template[`${prefix}_min_version_${platformKey}`] as string) ??
      this.gameConfig.minimumVersions[platform];

    const recommendedVersion =
      (template[`${prefix}_rec_version_${platformKey}`] as string) ??
      minimumVersion;

    const currentVersion = clientVersion;
    const cmpMin = semverCompare(currentVersion, minimumVersion);
    const cmpRec = semverCompare(currentVersion, recommendedVersion);

    let status: VersionCheckResult['status'];
    if (cmpMin < 0) {
      status = 'update_required';
    } else if (cmpRec < 0) {
      status = 'update_recommended';
    } else {
      status = 'ok';
    }

    return {
      currentVersion,
      minimumVersion,
      recommendedVersion,
      status,
      storeUrl: this.gameConfig.storeUrls,
      maintenanceMode: false,
    };
  }

  async getValue<T>(key: string, defaultValue: T): Promise<T> {
    const template = await this.getTemplate(this.gameConfig.gameId);
    const value = template[key];
    return value !== undefined ? (value as T) : defaultValue;
  }

  async getTemplate(_gameId: string): Promise<RemoteConfigTemplate> {
    const now = Date.now();

    if (this.cachedTemplate && now < this.cacheExpiresAt) {
      return this.cachedTemplate;
    }

    await this.refresh();
    return this.cachedTemplate!;
  }

  async refresh(): Promise<void> {
    const template = await this.remoteConfig.getTemplate();
    const parsed: RemoteConfigTemplate = {};

    for (const [key, param] of Object.entries(template.parameters ?? {})) {
      const defaultValue =
        param.defaultValue && 'value' in param.defaultValue
          ? (param.defaultValue as { value: string }).value
          : undefined;

      if (defaultValue !== undefined) {
        // Attempt type coercion
        if (defaultValue === 'true') parsed[key] = true;
        else if (defaultValue === 'false') parsed[key] = false;
        else if (!isNaN(Number(defaultValue)) && defaultValue !== '') {
          parsed[key] = Number(defaultValue);
        } else {
          try {
            parsed[key] = JSON.parse(defaultValue);
          } catch {
            parsed[key] = defaultValue;
          }
        }
      }
    }

    this.cachedTemplate = parsed;
    this.cacheExpiresAt = Date.now() + CACHE_TTL_MS;
  }
}
