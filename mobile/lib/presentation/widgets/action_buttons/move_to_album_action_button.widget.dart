import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/album/album_selector.widget.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/base_bottom_sheet.widget.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

class MoveToAlbumActionButton extends ConsumerWidget {
  final String albumId;
  final bool iconOnly;
  final bool menuItem;

  const MoveToAlbumActionButton({super.key, required this.albumId, this.iconOnly = false, this.menuItem = false});

  Future<RemoteAlbum?> _pickTargetAlbum(BuildContext context) {
    return showModalBottomSheet<RemoteAlbum>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        void onAlbumSelected(RemoteAlbum album) => Navigator.of(sheetContext).pop(album);

        return BaseBottomSheet(
          actions: const [],
          slivers: [
            MoveToAlbumHeader(onAlbumCreated: onAlbumSelected),
            AlbumSelector(onAlbumSelected: onAlbumSelected, excludedAlbumIds: {albumId}),
          ],
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          backgroundColor: context.isDarkTheme ? Colors.black : Colors.white,
        );
      },
    );
  }

  void _onTap(BuildContext context, WidgetRef ref) async {
    final assetIds = ref
        .read(multiSelectProvider)
        .selectedAssets
        .whereType<RemoteAsset>()
        .map((asset) => asset.id)
        .toList(growable: false);
    if (assetIds.isEmpty) {
      return;
    }

    final targetAlbum = await _pickTargetAlbum(context);
    if (targetAlbum == null || !context.mounted) {
      return;
    }

    final List<String> movedIds;
    try {
      movedIds = await ref
          .read(remoteAlbumProvider.notifier)
          .moveAssets(sourceAlbumId: albumId, targetAlbumId: targetAlbum.id, assetIds: assetIds);
    } catch (_) {
      if (context.mounted) {
        ImmichToast.show(
          context: context,
          msg: 'errors.error_moving_assets_to_album'.t(context: context),
          toastType: ToastType.error,
        );
      }
      return;
    }

    if (!context.mounted) {
      return;
    }

    final notMovedCount = assetIds.length - movedIds.length;
    final movedMessage = 'assets_moved_to_album_count'.t(context: context, args: {'count': movedIds.length});
    final notMovedMessage = 'assets_cannot_be_moved_to_album_count'.t(context: context, args: {'count': notMovedCount});

    if (movedIds.isEmpty) {
      ImmichToast.show(context: context, msg: notMovedMessage, toastType: ToastType.error);
      return;
    }

    ref.read(multiSelectProvider.notifier).reset();

    if (notMovedCount > 0) {
      ImmichToast.show(context: context, msg: '$movedMessage\n$notMovedMessage');
      return;
    }

    ImmichToast.show(context: context, msg: movedMessage, toastType: ToastType.success);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BaseActionButton(
      iconData: Icons.drive_file_move_outline,
      label: 'move_to_album'.t(context: context),
      iconOnly: iconOnly,
      menuItem: menuItem,
      onPressed: () => _onTap(context, ref),
      maxWidth: 100,
    );
  }
}
