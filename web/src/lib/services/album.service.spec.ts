import {
  addAssetsToAlbum,
  BulkIdErrorReason,
  moveAssetsToAlbum as moveToAlbum,
  removeAssetFromAlbum,
  type BulkIdResponseDto,
} from '@immich/sdk';
import { toastManager } from '@immich/ui';
import { vitest } from 'vitest';
import { goto } from '$app/navigation';
import { moveAssetsToAlbum } from '$lib/services/album.service';
import { handleError } from '$lib/utils/handle-error';
import { getFormatter } from '$lib/utils/i18n';

vitest.mock('@immich/ui', () => ({
  toastManager: {
    primary: vitest.fn(),
    warning: vitest.fn(),
  },
}));

vitest.mock('$app/navigation', () => ({
  goto: vitest.fn(),
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
      $t.mockImplementation((key: string) => key);
      vitest.mocked(getFormatter).mockResolvedValue($t);
    });

    it('should move every asset with a single request', async () => {
      vitest.mocked(moveToAlbum).mockResolvedValue([succeeded('asset-1'), succeeded('asset-2')]);

      const movedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2']);

      expect(movedIds).toEqual(['asset-1', 'asset-2']);
      expect(moveToAlbum).toHaveBeenCalledTimes(1);
      expect(moveToAlbum).toHaveBeenCalledWith({
        id: 'source',
        albumMoveAssetsDto: { targetAlbumId: 'destination', assetIds: ['asset-1', 'asset-2'] },
      });
      expect(addAssetsToAlbum).not.toHaveBeenCalled();
      expect(removeAssetFromAlbum).not.toHaveBeenCalled();
      expect($t).toHaveBeenCalledWith('assets_moved_to_album_count', { values: { count: 2 } });
      expect(toastManager.primary).toHaveBeenCalledTimes(1);
      expect(toastManager.warning).not.toHaveBeenCalled();
    });

    it('should open the target album from the success toast', async () => {
      vitest.mocked(moveToAlbum).mockResolvedValue([succeeded('asset-1')]);

      await moveAssetsToAlbum('source', 'destination', ['asset-1']);

      const [toast] = vitest.mocked(toastManager.primary).mock.calls[0];
      expect(toast).toEqual({
        description: 'assets_moved_to_album_count',
        button: { label: 'view_album', onclick: expect.any(Function) },
      });

      await (toast as { button: { onclick: () => unknown } }).button.onclick();

      expect(goto).toHaveBeenCalledWith('/albums/destination');
    });

    it('should report only the moved assets when some could not be moved', async () => {
      vitest
        .mocked(moveToAlbum)
        .mockResolvedValue([
          succeeded('asset-1'),
          failed('asset-2', BulkIdErrorReason.NotFound),
          failed('asset-3', BulkIdErrorReason.NoPermission),
        ]);

      const movedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2', 'asset-3']);

      expect(movedIds).toEqual(['asset-1']);
      expect($t).toHaveBeenCalledWith('assets_moved_to_album_count', { values: { count: 1 } });
      expect($t).toHaveBeenCalledWith('assets_cannot_be_moved_to_album_count', { values: { count: 2 } });
      expect(toastManager.primary).toHaveBeenCalledTimes(1);
      expect(toastManager.warning).toHaveBeenCalledExactlyOnceWith('assets_cannot_be_moved_to_album_count');
    });

    it('should count assets already in the target album as moved', async () => {
      vitest.mocked(moveToAlbum).mockResolvedValue([succeeded('new-in-target'), succeeded('already-in-target')]);

      const movedIds = await moveAssetsToAlbum('source', 'destination', ['new-in-target', 'already-in-target']);

      expect(movedIds).toEqual(['new-in-target', 'already-in-target']);
      expect($t).toHaveBeenCalledWith('assets_moved_to_album_count', { values: { count: 2 } });
      expect(toastManager.primary).toHaveBeenCalledTimes(1);
      expect(toastManager.warning).not.toHaveBeenCalled();
    });

    it('should not report a move when nothing could be moved', async () => {
      vitest
        .mocked(moveToAlbum)
        .mockResolvedValue([
          failed('asset-1', BulkIdErrorReason.NoPermission),
          failed('asset-2', BulkIdErrorReason.NotFound),
        ]);

      const movedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2']);

      expect(movedIds).toEqual([]);
      expect($t).toHaveBeenCalledWith('assets_cannot_be_moved_to_album_count', { values: { count: 2 } });
      expect(toastManager.primary).not.toHaveBeenCalled();
      expect(toastManager.warning).toHaveBeenCalledExactlyOnceWith('assets_cannot_be_moved_to_album_count');
    });

    it('should not return any ids when the request fails', async () => {
      const error = new Error('Network error');
      vitest.mocked(moveToAlbum).mockRejectedValue(error);

      const movedIds = await moveAssetsToAlbum('source', 'destination', ['asset-1', 'asset-2']);

      expect(movedIds).toEqual([]);
      expect(handleError).toHaveBeenCalledExactlyOnceWith(error, 'errors.error_moving_assets_to_album');
      expect(toastManager.primary).not.toHaveBeenCalled();
      expect(toastManager.warning).not.toHaveBeenCalled();
    });
  });
});
