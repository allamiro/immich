<script lang="ts">
  import AlbumPickerModal from '#lib/modals/AlbumPickerModal.svelte';
  import { moveAssetsToAlbumMutation } from '#lib/queries/album.query.ts';
  import { executeMutation } from '#lib/queries/client.ts';
  import { type AlbumResponseDto } from '@immich/sdk';
  import { t } from 'svelte-i18n';

  type Props = {
    assetIds: string[];
    sourceAlbum: AlbumResponseDto;
    onClose: (moved?: boolean) => void;
  };

  const { assetIds, sourceAlbum, onClose }: Props = $props();

  const handleClose = async (albums?: AlbumResponseDto[]) => {
    const [targetAlbum] = albums ?? [];
    if (!targetAlbum) {
      onClose();
      return;
    }

    const results = await executeMutation(moveAssetsToAlbumMutation, [
      { id: sourceAlbum.id, albumMoveAssetsDto: { targetAlbumId: targetAlbum.id, assetIds } },
    ]);
    onClose(results?.some(({ success }) => success) ?? false);
  };
</script>

<AlbumPickerModal
  onClose={handleClose}
  title={$t('move_to_album')}
  excludedAlbumIds={[sourceAlbum.id]}
  multiple={false}
/>
