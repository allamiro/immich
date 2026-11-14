import { DateTime } from 'luxon';
import { PassThrough } from 'node:stream';
import { defaults } from 'src/dtos/config.dto.js';
import { JobStatus, ReleaseChannel, SystemMetadataKey } from 'src/enum.js';
import { MaintenanceHealthRepository } from 'src/maintenance/maintenance-health.repository.js';
import { DatabaseBackupService } from 'src/services/database-backup.service.js';
import { ServerService } from 'src/services/server.service.js';
import { VersionService } from 'src/services/version.service.js';
import { systemConfigStub } from 'test/fixtures/system-config.stub.js';
import { factory } from 'test/small.factory.js';
import { ServiceMocks, automock, getMocks, mockDuplex, mockSpawn, newTestService } from 'test/utils.js';

vitest.mock('node:fs', () => ({ readFileSync: () => JSON.stringify({ version: '3.4.1-fork.1' }) }));

const mockRelease = (version: string) => ({ version, published_at: DateTime.utc().toISO() });

const upstreamVersion = {
  major: 3,
  minor: 4,
  patch: 1,
  prerelease: null,
  featureLevel: expect.any(Number),
};

describe('fork version 3.4.1-fork.1', () => {
  describe(VersionService.name, () => {
    let sut: VersionService;
    let mocks: ServiceMocks;

    beforeEach(() => {
      ({ sut, mocks } = newTestService(VersionService));
    });

    it('should report the upstream version to clients', () => {
      expect(sut.getVersion()).toEqual(upstreamVersion);
    });

    it('should record the fork label in the version history', async () => {
      mocks.versionHistory.getLatest.mockResolvedValue({ id: 'version-1', createdAt: new Date(), version: '3.4.1' });
      mocks.versionHistory.create.mockResolvedValue(factory.versionHistory());

      await sut.onBootstrap();

      expect(mocks.versionHistory.create).toHaveBeenCalledWith({ version: '3.4.1-fork.1' });
    });

    it.each([ReleaseChannel.Stable, ReleaseChannel.ReleaseCandidate])(
      'should not announce the upstream release it is based on (%s channel)',
      async (channel) => {
        mocks.systemMetadata.get.mockImplementation((key) =>
          Promise.resolve(
            key === SystemMetadataKey.SystemConfig ? { newVersionCheck: { enabled: true, channel } } : null,
          ),
        );
        mocks.serverInfo.getLatestRelease.mockResolvedValue(mockRelease('v3.4.1'));

        await expect(sut.handleVersionCheck()).resolves.toBe(JobStatus.Success);

        expect(mocks.systemMetadata.set).toHaveBeenCalledWith(SystemMetadataKey.VersionCheckState, {
          checkedAt: expect.any(String),
          releaseVersion: 'v3.4.1',
        });
        expect(mocks.logger.log).not.toHaveBeenCalled();
        expect(mocks.websocket.clientBroadcast).not.toHaveBeenCalled();
      },
    );

    it('should not announce an older upstream release', async () => {
      mocks.serverInfo.getLatestRelease.mockResolvedValue(mockRelease('v3.4.0'));

      await expect(sut.handleVersionCheck()).resolves.toBe(JobStatus.Success);

      expect(mocks.websocket.clientBroadcast).not.toHaveBeenCalled();
    });

    it('should announce the next upstream patch release', async () => {
      mocks.serverInfo.getLatestRelease.mockResolvedValue(mockRelease('v3.4.2'));

      await expect(sut.handleVersionCheck()).resolves.toBe(JobStatus.Success);

      expect(mocks.logger.log).toHaveBeenCalledWith(expect.stringMatching(/^Found v3\.4\.2, released at /));
      expect(mocks.websocket.clientBroadcast).toHaveBeenCalledWith('on_new_release', {
        isAvailable: true,
        checkedAt: expect.any(String),
        serverVersion: upstreamVersion,
        releaseVersion: { major: 3, minor: 4, patch: 2, prerelease: null, featureLevel: expect.any(Number) },
        type: 'patch',
      });
    });

    it('should announce the next upstream minor release', async () => {
      mocks.serverInfo.getLatestRelease.mockResolvedValue(mockRelease('v3.5.0'));

      await expect(sut.handleVersionCheck()).resolves.toBe(JobStatus.Success);

      expect(mocks.websocket.clientBroadcast).toHaveBeenCalledWith(
        'on_new_release',
        expect.objectContaining({ isAvailable: true, type: 'minor' }),
      );
    });

    it('should tell a connecting client that the stored upstream release is not new', async () => {
      mocks.systemMetadata.get.mockImplementation((key) =>
        Promise.resolve(
          key === SystemMetadataKey.VersionCheckState
            ? { checkedAt: '2026-11-15T00:00:00.000Z', releaseVersion: 'v3.4.1' }
            : { newVersionCheck: { ...defaults.newVersionCheck, enabled: true } },
        ),
      );

      await sut.onWebsocketConnection({ userId: '42' });

      expect(mocks.websocket.clientSend).toHaveBeenCalledWith('on_server_version', '42', upstreamVersion);
      expect(mocks.websocket.clientSend).toHaveBeenCalledWith('on_new_release', '42', {
        isAvailable: false,
        checkedAt: '2026-11-15T00:00:00.000Z',
        serverVersion: upstreamVersion,
        releaseVersion: upstreamVersion,
        type: null,
      });
    });
  });

  describe(ServerService.name, () => {
    let sut: ServerService;
    let mocks: ServiceMocks;

    beforeEach(() => {
      ({ sut, mocks } = newTestService(ServerService));
    });

    it('should show the fork label and link to the upstream release', async () => {
      mocks.serverInfo.getBuildVersions.mockResolvedValue({ nodejs: 'v24.0.0' } as never);

      await expect(sut.getAboutInfo()).resolves.toEqual(
        expect.objectContaining({
          version: 'v3.4.1-fork.1',
          versionUrl: 'https://github.com/immich-app/immich/releases/tag/v3.4.1',
        }),
      );
    });

    it('should download the apks of the upstream release', () => {
      expect(sut.getApkLinks().universal).toBe(
        'https://github.com/immich-app/immich/releases/download/v3.4.1/app-release.apk',
      );
    });
  });

  describe(DatabaseBackupService.name, () => {
    it('should name backups after the upstream version the schema belongs to', async () => {
      const mocks = getMocks();
      mocks.process.isCommandAvailable.mockResolvedValue(false);
      mocks.process.spawn.mockReturnValue(mockSpawn(0, 'data', ''));
      mocks.process.spawnDuplexStream.mockImplementation(() => mockDuplex()('command', 0, 'data', ''));
      mocks.storage.readdir.mockResolvedValue([]);
      mocks.storage.rename.mockResolvedValue();
      mocks.storage.createWriteStream.mockReturnValue(new PassThrough());
      mocks.systemMetadata.get.mockResolvedValue(systemConfigStub.backupEnabled);
      mocks.database.getPostgresVersion.mockResolvedValue('14.17 (Debian 14.17-1.pgdg120+1)');
      const sut = new DatabaseBackupService(
        mocks.logger as never,
        mocks.storage as never,
        mocks.config,
        mocks.systemMetadata as never,
        mocks.process,
        mocks.database as never,
        mocks.user as never,
        mocks.cron as never,
        mocks.job as never,
        automock(MaintenanceHealthRepository, { args: [mocks.logger], strict: false }) as never,
      );

      await expect(sut.handleBackupDatabase()).resolves.toBe(JobStatus.Success);

      expect(mocks.storage.rename).toHaveBeenCalledWith(
        expect.stringMatching(/\/immich-db-backup-\d{8}T\d{6}-v3\.4\.1-pg14\.17\.sql\.gz\.tmp$/),
        expect.stringMatching(/\/immich-db-backup-\d{8}T\d{6}-v3\.4\.1-pg14\.17\.sql\.gz$/),
      );
    });
  });
});
