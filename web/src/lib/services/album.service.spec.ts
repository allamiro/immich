import { addAssetsToAlbum, BulkIdErrorReason, removeAssetFromAlbum, type BulkIdResponseDto } from '@immich/sdk';
import { toastManager } from '@immich/ui';
import { vitest } from 'vitest';
import { moveAssetsToAlbum } from '$lib/services/album.service';
import { handleError } from '$lib/utils/handle-error';
import { getFormatter } from '$lib/utils/i18n';

vitest.mock('@immich/ui', () => ({
  toastManager: {
    primary: vitest.fn(),
    warning: vitest.fn(),
  },
}));

vitest.mock('$lib/utils/i18n', () => ({
  getFormatter: vitest.fn(),
  getPreferredLocale: vitest.fn(),
}));

vitest.mock('$lib/utils/handle-error', () => ({
  handleError: vitest.fn(),
}));

vitest.mock('@immich/sdk');

const succeeded = (id: string): BulkIdResponseDto => ({ id, success: true });
const failed = (id: string, error: BulkIdErrorReason): BulkIdResponseDto => ({ id, success: false, error });

describe('AlbumService', () => {
  describe('moveAssetsToAlbum', () => {
    const $t = vitest.fn();

    beforeEach(() => {
      vitest.resetAllMocks();
      $t.mockReturnValue('formatter');
      vitest.mocked(getFormatter).mockResolvedValue($t);
    });

    it('should remove every added asset from the source album', async () => {
      vitest.mocked(addAssetsToAlbum).mockResolvedValue([succeeded('asset-1'), succeeded('asset-2')]);
      vitest.mocked(removeAssetFromAlbum).mockResolvedValue([succeeded('asset-1'), succeeded('asset-2')]);

      const removedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2']);

      expect(removedIds).toEqual(['asset-1', 'asset-2']);
      expect(addAssetsToAlbum).toHaveBeenCalledWith({ id: 'destination', bulkIdsDto: { ids: ['asset-1', 'asset-2'] } });
      expect(removeAssetFromAlbum).toHaveBeenCalledWith({ id: 'source', bulkIdsDto: { ids: ['asset-1', 'asset-2'] } });
      expect($t).toHaveBeenCalledWith('assets_moved_to_album_count', { values: { count: 2 } });
      expect(toastManager.primary).toHaveBeenCalledTimes(1);
      expect(toastManager.warning).not.toHaveBeenCalled();
    });

    it('should also remove assets already in the destination album from the source album', async () => {
      vitest
        .mocked(addAssetsToAlbum)
        .mockResolvedValue([succeeded('asset-1'), failed('asset-2', BulkIdErrorReason.Duplicate)]);
      vitest.mocked(removeAssetFromAlbum).mockResolvedValue([succeeded('asset-1'), succeeded('asset-2')]);

      const removedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2']);

      expect(removedIds).toEqual(['asset-1', 'asset-2']);
      expect(removeAssetFromAlbum).toHaveBeenCalledWith({ id: 'source', bulkIdsDto: { ids: ['asset-1', 'asset-2'] } });
      expect($t).toHaveBeenCalledWith('assets_moved_to_album_count', { values: { count: 2 } });
      expect(toastManager.warning).not.toHaveBeenCalled();
    });

    it('should count assets as moved when all of them were already in the destination album', async () => {
      vitest
        .mocked(addAssetsToAlbum)
        .mockResolvedValue([
          failed('asset-1', BulkIdErrorReason.Duplicate),
          failed('asset-2', BulkIdErrorReason.Duplicate),
        ]);
      vitest.mocked(removeAssetFromAlbum).mockResolvedValue([succeeded('asset-1'), succeeded('asset-2')]);

      const removedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2']);

      expect(removedIds).toEqual(['asset-1', 'asset-2']);
      expect(removeAssetFromAlbum).toHaveBeenCalledWith({ id: 'source', bulkIdsDto: { ids: ['asset-1', 'asset-2'] } });
      expect($t).toHaveBeenCalledWith('assets_moved_to_album_count', { values: { count: 2 } });
      expect(toastManager.warning).not.toHaveBeenCalled();
    });

    it('should keep assets that could not be added in the source album', async () => {
      vitest
        .mocked(addAssetsToAlbum)
        .mockResolvedValue([succeeded('asset-1'), failed('asset-2', BulkIdErrorReason.NoPermission)]);
      vitest.mocked(removeAssetFromAlbum).mockResolvedValue([succeeded('asset-1')]);

      const removedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2']);

      expect(removedIds).toEqual(['asset-1']);
      expect(removeAssetFromAlbum).toHaveBeenCalledWith({ id: 'source', bulkIdsDto: { ids: ['asset-1'] } });
      expect($t).toHaveBeenCalledWith('assets_moved_to_album_count', { values: { count: 1 } });
      expect(toastManager.warning).not.toHaveBeenCalled();
    });

    it('should report only the assets removed from the source album as moved', async () => {
      vitest.mocked(addAssetsToAlbum).mockResolvedValue([succeeded('asset-1'), succeeded('asset-2')]);
      vitest
        .mocked(removeAssetFromAlbum)
        .mockResolvedValue([succeeded('asset-1'), failed('asset-2', BulkIdErrorReason.NoPermission)]);

      const removedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2']);

      expect(removedIds).toEqual(['asset-1']);
      expect($t).toHaveBeenCalledWith('assets_moved_to_album_count', { values: { count: 1 } });
      expect($t).toHaveBeenCalledWith('assets_cannot_be_removed_from_album_count', { values: { count: 1 } });
      expect(toastManager.primary).toHaveBeenCalledTimes(1);
      expect(toastManager.warning).toHaveBeenCalledWith('formatter');
    });

    it('should not report a move when nothing could be removed from the source album', async () => {
      vitest.mocked(addAssetsToAlbum).mockResolvedValue([succeeded('asset-1')]);
      vitest.mocked(removeAssetFromAlbum).mockResolvedValue([failed('asset-1', BulkIdErrorReason.NoPermission)]);

      const removedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1']);

      expect(removedIds).toEqual([]);
      expect($t).toHaveBeenCalledWith('assets_cannot_be_removed_from_album_count', { values: { count: 1 } });
      expect(toastManager.primary).not.toHaveBeenCalled();
      expect(toastManager.warning).toHaveBeenCalledWith('formatter');
    });

    it('should not remove anything when no asset could be added', async () => {
      vitest
        .mocked(addAssetsToAlbum)
        .mockResolvedValue([
          failed('asset-1', BulkIdErrorReason.NoPermission),
          failed('asset-2', BulkIdErrorReason.NotFound),
        ]);

      const removedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2']);

      expect(removedIds).toEqual([]);
      expect(removeAssetFromAlbum).not.toHaveBeenCalled();
      expect($t).toHaveBeenCalledWith('assets_cannot_be_added_to_album_count', { values: { count: 2 } });
      expect(toastManager.primary).not.toHaveBeenCalled();
      expect(toastManager.warning).toHaveBeenCalledWith('formatter');
    });

    it('should not remove anything when the add request fails', async () => {
      const error = new Error('Network error');
      vitest.mocked(addAssetsToAlbum).mockRejectedValue(error);

      const removedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2']);

      expect(removedIds).toEqual([]);
      expect(removeAssetFromAlbum).not.toHaveBeenCalled();
      expect(handleError).toHaveBeenCalledWith(error, 'formatter');
      expect(toastManager.primary).not.toHaveBeenCalled();
    });
  });
});
