<script lang="ts">
  import AlbumPickerModal from '$lib/modals/AlbumPickerModal.svelte';
  import { moveAssetsToAlbum } from '$lib/services/album.service';
  import { type AlbumResponseDto } from '@immich/sdk';
  import { t } from 'svelte-i18n';

  type Props = {
    assetIds: string[];
    sourceAlbum: AlbumResponseDto;
    onClose: (removedAssetIds?: string[]) => void;
  };

  const { assetIds, sourceAlbum, onClose }: Props = $props();

  const handleClose = async (albums?: AlbumResponseDto[]) => {
    const [destinationAlbum] = albums ?? [];
    if (!destinationAlbum) {
      onClose();
      return;
    }
    onClose(await moveAssetsToAlbum(sourceAlbum.id, destinationAlbum.id, assetIds));
  };
</script>

<AlbumPickerModal
  onClose={handleClose}
  title={$t('move_to_album')}
  excludedAlbumIds={[sourceAlbum.id]}
  multiple={false}
/>
