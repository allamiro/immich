import { eventManager } from '#lib/managers/event-manager.svelte.ts';
import { moveAssetsToAlbumMutation } from '#lib/queries/album.query.ts';
import { executeMutation } from '#lib/queries/client.ts';
import { getFormatter } from '#lib/utils/i18n.ts';
import { test } from '#test/unit/fixtures.ts';
import { BulkIdErrorReason, type BulkIdResponseDto } from '@immich/sdk';
import { toastManager } from '@immich/ui';
import { afterEach, beforeEach, describe, expect, vi, type MockInstance } from 'vitest';

const sourceAlbumId = 'source';
const targetAlbumId = 'target';

const succeeded = (id: string): BulkIdResponseDto => ({ id, success: true });
const failed = (id: string, error: BulkIdErrorReason): BulkIdResponseDto => ({ id, success: false, error });

const move = (assetIds: string[]) =>
  executeMutation(moveAssetsToAlbumMutation, [{ id: sourceAlbumId, albumMoveAssetsDto: { targetAlbumId, assetIds } }]);

describe('moveAssetsToAlbumMutation', () => {
  let primary: MockInstance<typeof toastManager.primary>;
  let warning: MockInstance<typeof toastManager.warning>;
  let danger: MockInstance<typeof toastManager.danger>;
  let emit: MockInstance<typeof eventManager.emit>;

  beforeEach(() => {
    primary = vi.spyOn(toastManager, 'primary');
    warning = vi.spyOn(toastManager, 'warning');
    danger = vi.spyOn(toastManager, 'danger');
    emit = vi.spyOn(eventManager, 'emit');
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  test('moves every asset with a single request', async ({ api, settle }) => {
    const $t = await getFormatter();
    api.on({ moveAssetsToAlbum: () => ({ json: [succeeded('asset-1'), succeeded('asset-2')] }) });

    await move(['asset-1', 'asset-2']);
    await settle();

    expect(api.moveAssetsToAlbum).toHaveBeenCalledWith({
      params: { id: sourceAlbumId },
      body: { targetAlbumId, assetIds: ['asset-1', 'asset-2'] },
    });
    expect(api.moveAssetsToAlbum.calls).toHaveLength(1);
    expect(api.addAssetsToAlbum.calls).toHaveLength(0);
    expect(api.removeAssetFromAlbum.calls).toHaveLength(0);
    expect(primary).toHaveBeenCalledExactlyOnceWith(
      {
        description: $t('assets_moved_to_album_count', { values: { count: 2 } }),
        button: { label: $t('view_album'), onclick: expect.any(Function) },
      },
      { timeout: 5000 },
    );
    expect(warning).not.toHaveBeenCalled();
    expect(emit).toHaveBeenCalledExactlyOnceWith('AlbumRemoveAssets', {
      assetIds: ['asset-1', 'asset-2'],
      albumIds: [sourceAlbumId],
    });
  });

  test('opens the target album from the success toast', async ({ api, router, settle }) => {
    api.on({ moveAssetsToAlbum: () => ({ json: [succeeded('asset-1')] }) });

    await move(['asset-1']);
    await settle();

    expect(api.moveAssetsToAlbum).toHaveBeenCalled();
    const [toast] = primary.mock.calls[0];
    await (toast as { button: { onclick: () => unknown } }).button.onclick();

    expect(router.url.pathname).toBe(`/albums/${targetAlbumId}`);
  });

  test('reports only the moved assets when some could not be moved', async ({ api, settle }) => {
    const $t = await getFormatter();
    api.on({
      moveAssetsToAlbum: () => ({
        json: [
          succeeded('asset-1'),
          failed('asset-2', BulkIdErrorReason.NotFound),
          failed('asset-3', BulkIdErrorReason.NoPermission),
        ],
      }),
    });

    await move(['asset-1', 'asset-2', 'asset-3']);
    await settle();

    expect(api.moveAssetsToAlbum).toHaveBeenCalled();
    expect(primary).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({ description: $t('assets_moved_to_album_count', { values: { count: 1 } }) }),
      { timeout: 5000 },
    );
    expect(warning).toHaveBeenCalledExactlyOnceWith(
      $t('assets_cannot_be_moved_to_album_count', { values: { count: 2 } }),
    );
    expect(emit).toHaveBeenCalledExactlyOnceWith('AlbumRemoveAssets', {
      assetIds: ['asset-1'],
      albumIds: [sourceAlbumId],
    });
  });

  test('does not report a move when nothing could be moved', async ({ api, settle }) => {
    const $t = await getFormatter();
    api.on({
      moveAssetsToAlbum: () => ({
        json: [failed('asset-1', BulkIdErrorReason.NoPermission), failed('asset-2', BulkIdErrorReason.NotFound)],
      }),
    });

    await move(['asset-1', 'asset-2']);
    await settle();

    expect(api.moveAssetsToAlbum).toHaveBeenCalled();
    expect(primary).not.toHaveBeenCalled();
    expect(warning).toHaveBeenCalledExactlyOnceWith(
      $t('assets_cannot_be_moved_to_album_count', { values: { count: 2 } }),
    );
    expect(emit).not.toHaveBeenCalled();
  });

  test('shows one error and moves nothing when the request fails', async ({ api, logger, settle }) => {
    api.on({
      moveAssetsToAlbum: () => ({ status: 500, json: { message: 'Server error', statusCode: 500 } }),
    });

    const results = await move(['asset-1', 'asset-2']);
    await settle();

    expect(results).toBeUndefined();
    expect(api.moveAssetsToAlbum).toHaveBeenCalled();
    expect(logger.error).toHaveBeenCalledWith(/handleError/);
    expect(danger).toHaveBeenCalledTimes(1);
    expect(primary).not.toHaveBeenCalled();
    expect(warning).not.toHaveBeenCalled();
    expect(emit).not.toHaveBeenCalled();
  });
});
