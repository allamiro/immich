<script lang="ts">
  import AlbumPickerModal from '$lib/modals/AlbumPickerModal.svelte';
  import { moveAssetsToAlbum } from '$lib/services/album.service';
  import { type AlbumResponseDto } from '@immich/sdk';
  import { t } from 'svelte-i18n';

  type Props = {
    assetIds: string[];
    sourceAlbum: AlbumResponseDto;
    onClose: () => void;
  };

  const { assetIds, sourceAlbum, onClose }: Props = $props();

  const handleClose = async (albums?: AlbumResponseDto[]) => {
    const dest = albums?.[0];
    if (!dest) {
      onClose();
      return;
    }
    await moveAssetsToAlbum(sourceAlbum.id, dest.id, assetIds);
    onClose();
  };
</script>

<AlbumPickerModal onClose={handleClose} title={$t('move_to_album')} excludedAlbumIds={[sourceAlbum.id]} />
