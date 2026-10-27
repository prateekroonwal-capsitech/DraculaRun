import { injectable, inject } from 'inversify';
import { Bucket } from '@google-cloud/storage';
import { IStorageService, SignedUrlOptions, TYPES } from '@studio/core';

@injectable()
export class FirebaseStorageService implements IStorageService {
  constructor(
    @inject(TYPES.Infrastructure.FirebaseStorage)
    private readonly bucket: Bucket
  ) {}

  async getSignedUrl(path: string, options: SignedUrlOptions): Promise<string> {
    const [url] = await this.bucket.file(path).getSignedUrl({
      action: options.action,
      expires: Date.now() + options.expiresInSeconds * 1000,
      contentType: options.contentType,
    });
    return url;
  }

  async delete(path: string): Promise<void> {
    await this.bucket.file(path).delete({ ignoreNotFound: true });
  }

  async exists(path: string): Promise<boolean> {
    const [exists] = await this.bucket.file(path).exists();
    return exists;
  }

  async copy(sourcePath: string, destPath: string): Promise<void> {
    await this.bucket.file(sourcePath).copy(this.bucket.file(destPath));
  }
}
