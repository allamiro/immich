import { Kysely, sql } from 'kysely';
import { BulkIdErrorReason } from 'src/dtos/asset-ids.response.dto.js';
import { AlbumUserRole } from 'src/enum.js';
import { AccessRepository } from 'src/repositories/access.repository.js';
import { AlbumRepository } from 'src/repositories/album.repository.js';
import { AssetRepository } from 'src/repositories/asset.repository.js';
import { EventRepository } from 'src/repositories/event.repository.js';
import { LoggingRepository } from 'src/repositories/logging.repository.js';
import { UserRepository } from 'src/repositories/user.repository.js';
import { DB } from 'src/schema/index.js';
import { AlbumService } from 'src/services/album.service.js';
import { newMediumService } from 'test/medium.factory.js';
import { factory } from 'test/small.factory.js';
import { getKyselyDB } from 'test/utils.js';

let defaultDatabase: Kysely<DB>;

const setup = (db?: Kysely<DB>) => {
  const service = newMediumService(AlbumService, {
    database: db || defaultDatabase,
    real: [AccessRepository, AlbumRepository, AssetRepository, UserRepository],
    mock: [EventRepository, LoggingRepository],
  });
  service.ctx.getMock(EventRepository).emit.mockResolvedValue();
  return service;
};

beforeAll(async () => {
  defaultDatabase = await getKyselyDB();
});

describe(AlbumService.name, () => {
  describe('removeAssets', () => {
    it('should not remove assets from an album of another user', async () => {
      const { sut, ctx } = setup();
      const { user } = await ctx.newUser();
      const { user: otherUser } = await ctx.newUser();
      const { asset } = await ctx.newAsset({ ownerId: user.id });
      const { album } = await ctx.newAlbum({ ownerId: user.id }, [asset.id]);

      await expect(sut.removeAssets(factory.auth({ user: otherUser }), album.id, { ids: [asset.id] })).rejects.toThrow(
        'Not found or no albumAsset.delete access',
      );
      await expect(ctx.get(AlbumRepository).getAssetIds(album.id, [asset.id])).resolves.toContain(asset.id);
    });
  });

  describe('moveAssets', () => {
    it('should move assets from the source album to the target album', async () => {
      const { sut, ctx } = setup();
      const albumRepo = ctx.get(AlbumRepository);
      const { user } = await ctx.newUser();
      const auth = factory.auth({ user });
      const { asset: asset1 } = await ctx.newAsset({ ownerId: user.id });
      const { asset: asset2 } = await ctx.newAsset({ ownerId: user.id });
      const { asset: asset3 } = await ctx.newAsset({ ownerId: user.id });
      const { album: source } = await ctx.newAlbum({ ownerId: user.id, albumThumbnailAssetId: asset1.id }, [
        asset1.id,
        asset2.id,
        asset3.id,
      ]);
      const { album: target } = await ctx.newAlbum({ ownerId: user.id });

      await expect(
        sut.moveAssets(auth, source.id, { targetAlbumId: target.id, assetIds: [asset1.id, asset2.id] }),
      ).resolves.toEqual([
        { id: asset1.id, success: true },
        { id: asset2.id, success: true },
      ]);

      const assetIds = [asset1.id, asset2.id, asset3.id];
      await expect(albumRepo.getAssetIds(source.id, assetIds)).resolves.toEqual(new Set([asset3.id]));
      await expect(albumRepo.getAssetIds(target.id, assetIds)).resolves.toEqual(new Set([asset1.id, asset2.id]));
      await expect(albumRepo.getById(source.id)).resolves.toMatchObject({ albumThumbnailAssetId: asset3.id });
      await expect(albumRepo.getById(target.id)).resolves.toMatchObject({ albumThumbnailAssetId: asset1.id });
      expect(ctx.getMock(EventRepository).emit).toHaveBeenCalledTimes(2);
      expect(ctx.getMock(EventRepository).emit).toHaveBeenCalledWith('AlbumUpdate', {
        id: target.id,
        userIds: [user.id],
        recipientIds: [],
      });
      expect(ctx.getMock(EventRepository).emit).toHaveBeenCalledWith('AlbumUpdate', {
        id: source.id,
        userIds: [user.id],
        recipientIds: [],
      });
    });

    it('should remove an asset from the source album when it is already in the target album', async () => {
      const { sut, ctx } = setup();
      const albumRepo = ctx.get(AlbumRepository);
      const { user } = await ctx.newUser();
      const auth = factory.auth({ user });
      const { asset } = await ctx.newAsset({ ownerId: user.id });
      const { album: source } = await ctx.newAlbum({ ownerId: user.id }, [asset.id]);
      const { album: target } = await ctx.newAlbum({ ownerId: user.id }, [asset.id]);

      await expect(
        sut.moveAssets(auth, source.id, { targetAlbumId: target.id, assetIds: [asset.id] }),
      ).resolves.toEqual([{ id: asset.id, success: true }]);

      await expect(albumRepo.getAssetIds(source.id, [asset.id])).resolves.toEqual(new Set());
      await expect(albumRepo.getAssetIds(target.id, [asset.id])).resolves.toEqual(new Set([asset.id]));
    });

    it('should not move assets that are not in the source album', async () => {
      const { sut, ctx } = setup();
      const albumRepo = ctx.get(AlbumRepository);
      const { user } = await ctx.newUser();
      const auth = factory.auth({ user });
      const { asset } = await ctx.newAsset({ ownerId: user.id });
      const { album: source } = await ctx.newAlbum({ ownerId: user.id });
      const { album: target } = await ctx.newAlbum({ ownerId: user.id });

      await expect(
        sut.moveAssets(auth, source.id, { targetAlbumId: target.id, assetIds: [asset.id] }),
      ).resolves.toEqual([{ id: asset.id, success: false, error: BulkIdErrorReason.NOT_FOUND }]);

      await expect(albumRepo.getAssetIds(source.id, [asset.id])).resolves.toEqual(new Set());
      await expect(albumRepo.getAssetIds(target.id, [asset.id])).resolves.toEqual(new Set());
    });

    it('should only move the assets the user has access to', async () => {
      const { sut, ctx } = setup();
      const albumRepo = ctx.get(AlbumRepository);
      const { user } = await ctx.newUser();
      const { user: otherUser } = await ctx.newUser();
      const auth = factory.auth({ user });
      const { asset } = await ctx.newAsset({ ownerId: user.id });
      const { asset: otherAsset } = await ctx.newAsset({ ownerId: otherUser.id });
      const { album: source } = await ctx.newAlbum({ ownerId: user.id }, [asset.id, otherAsset.id]);
      const { album: target } = await ctx.newAlbum({ ownerId: otherUser.id });
      await ctx.newAlbumUser({ albumId: target.id, userId: user.id, role: AlbumUserRole.Editor });
      await ctx.softDeleteAsset(otherAsset.id);

      await expect(
        sut.moveAssets(auth, source.id, { targetAlbumId: target.id, assetIds: [asset.id, otherAsset.id] }),
      ).resolves.toEqual([
        { id: asset.id, success: true },
        { id: otherAsset.id, success: false, error: BulkIdErrorReason.NO_PERMISSION },
      ]);

      const assetIds = [asset.id, otherAsset.id];
      await expect(albumRepo.getAssetIds(source.id, assetIds)).resolves.toEqual(new Set([otherAsset.id]));
      await expect(albumRepo.getAssetIds(target.id, assetIds)).resolves.toEqual(new Set([asset.id]));
      expect(ctx.getMock(EventRepository).emit).toHaveBeenCalledTimes(2);
      expect(ctx.getMock(EventRepository).emit).toHaveBeenCalledWith('AlbumUpdate', {
        id: target.id,
        userIds: expect.arrayContaining([user.id, otherUser.id]),
        recipientIds: [otherUser.id],
      });
      expect(ctx.getMock(EventRepository).emit).toHaveBeenCalledWith('AlbumUpdate', {
        id: source.id,
        userIds: [user.id],
        recipientIds: [],
      });
    });

    it('should move an asset of another user that is shared through the source album', async () => {
      const { sut, ctx } = setup();
      const albumRepo = ctx.get(AlbumRepository);
      const { user } = await ctx.newUser();
      const { user: otherUser } = await ctx.newUser();
      const auth = factory.auth({ user });
      const { asset: otherAsset } = await ctx.newAsset({ ownerId: otherUser.id });
      const { album: source } = await ctx.newAlbum({ ownerId: user.id }, [otherAsset.id]);
      const { album: target } = await ctx.newAlbum({ ownerId: user.id });

      await expect(
        sut.moveAssets(auth, source.id, { targetAlbumId: target.id, assetIds: [otherAsset.id] }),
      ).resolves.toEqual([{ id: otherAsset.id, success: true }]);

      await expect(albumRepo.getAssetIds(source.id, [otherAsset.id])).resolves.toEqual(new Set());
      await expect(albumRepo.getAssetIds(target.id, [otherAsset.id])).resolves.toEqual(new Set([otherAsset.id]));
    });

    it('should not move assets to an album the user can only view', async () => {
      const { sut, ctx } = setup();
      const albumRepo = ctx.get(AlbumRepository);
      const { user } = await ctx.newUser();
      const { user: otherUser } = await ctx.newUser();
      const auth = factory.auth({ user });
      const { asset } = await ctx.newAsset({ ownerId: user.id });
      const { album: source } = await ctx.newAlbum({ ownerId: user.id }, [asset.id]);
      const { album: target } = await ctx.newAlbum({ ownerId: otherUser.id });
      await ctx.newAlbumUser({ albumId: target.id, userId: user.id, role: AlbumUserRole.Viewer });

      await expect(sut.moveAssets(auth, source.id, { targetAlbumId: target.id, assetIds: [asset.id] })).rejects.toThrow(
        'Not found or no albumAsset.create access',
      );

      await expect(albumRepo.getAssetIds(source.id, [asset.id])).resolves.toEqual(new Set([asset.id]));
      await expect(albumRepo.getAssetIds(target.id, [asset.id])).resolves.toEqual(new Set());
    });

    it('should leave both albums untouched when removing from the source album fails', async () => {
      const { sut, ctx } = setup(await getKyselyDB());
      const albumRepo = ctx.get(AlbumRepository);
      const { user } = await ctx.newUser();
      const auth = factory.auth({ user });
      const { asset } = await ctx.newAsset({ ownerId: user.id });
      const { album: source } = await ctx.newAlbum({ ownerId: user.id }, [asset.id]);
      const { album: target } = await ctx.newAlbum({ ownerId: user.id });

      await sql`
        create function album_asset_delete_failure () returns trigger language plpgsql as $$
        begin
          raise exception 'album_asset delete failure';
        end
        $$
      `.execute(ctx.database);
      await sql`
        create trigger album_asset_delete_failure before delete on album_asset for each statement
        execute function album_asset_delete_failure ()
      `.execute(ctx.database);

      await expect(sut.moveAssets(auth, source.id, { targetAlbumId: target.id, assetIds: [asset.id] })).rejects.toThrow(
        'album_asset delete failure',
      );

      await expect(albumRepo.getAssetIds(source.id, [asset.id])).resolves.toEqual(new Set([asset.id]));
      await expect(albumRepo.getAssetIds(target.id, [asset.id])).resolves.toEqual(new Set());
    });
  });

  describe('database triggers', () => {
    it('should cascade delete an album when the owner is deleted', async () => {
      const { ctx } = setup();
      const { user } = await ctx.newUser();
      const { album } = await ctx.newAlbum({ ownerId: user.id });

      await ctx.get(UserRepository).delete({ id: user.id }, true);

      await expect(ctx.database.selectFrom('album').selectAll().where('id', '=', album.id).execute()).resolves.toEqual(
        [],
      );
      await expect(
        ctx.database.selectFrom('album_user').selectAll().where('albumId', '=', album.id).execute(),
      ).resolves.toEqual([]);
    });
  });
});
