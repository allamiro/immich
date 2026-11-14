import { Kysely, sql } from 'kysely';
import { BulkIdErrorReason } from 'src/dtos/asset-ids.response.dto';
import { AlbumUserRole } from 'src/enum';
import { AccessRepository } from 'src/repositories/access.repository';
import { AlbumRepository } from 'src/repositories/album.repository';
import { EventRepository } from 'src/repositories/event.repository';
import { LoggingRepository } from 'src/repositories/logging.repository';
import { DB } from 'src/schema';
import { AlbumService } from 'src/services/album.service';
import { newMediumService } from 'test/medium.factory';
import { factory } from 'test/small.factory';
import { getKyselyDB } from 'test/utils';

let defaultDatabase: Kysely<DB>;

const setup = (db?: Kysely<DB>) => {
  return newMediumService(AlbumService, {
    database: db || defaultDatabase,
    real: [AccessRepository, AlbumRepository],
    mock: [EventRepository, LoggingRepository],
  });
};

beforeAll(async () => {
  defaultDatabase = await getKyselyDB();
});

describe(AlbumService.name, () => {
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
      await expect(albumRepo.getById(source.id, { withAssets: false })).resolves.toMatchObject({
        albumThumbnailAssetId: asset3.id,
      });
      await expect(albumRepo.getById(target.id, { withAssets: false })).resolves.toMatchObject({
        albumThumbnailAssetId: asset1.id,
      });
      expect(ctx.getMock(EventRepository).emit).not.toHaveBeenCalled();
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
      ctx.getMock(EventRepository).emit.mockResolvedValue();

      await expect(
        sut.moveAssets(auth, source.id, { targetAlbumId: target.id, assetIds: [asset.id, otherAsset.id] }),
      ).resolves.toEqual([
        { id: asset.id, success: true },
        { id: otherAsset.id, success: false, error: BulkIdErrorReason.NO_PERMISSION },
      ]);

      const assetIds = [asset.id, otherAsset.id];
      await expect(albumRepo.getAssetIds(source.id, assetIds)).resolves.toEqual(new Set([otherAsset.id]));
      await expect(albumRepo.getAssetIds(target.id, assetIds)).resolves.toEqual(new Set([asset.id]));
      expect(ctx.getMock(EventRepository).emit).toHaveBeenCalledExactlyOnceWith('AlbumUpdate', {
        id: target.id,
        recipientId: otherUser.id,
      });
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
});
