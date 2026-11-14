import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/actions/action.dart';
import 'package:immich_mobile/presentation/widgets/album/album_selector.widget.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/base_bottom_sheet.widget.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';

typedef _MoveScope = ({ActionSource source, bool ownsAlbum});

final _stateProvider = Provider.family.autoDispose<List<String>?, _MoveScope>((ref, scope) {
  final assets = ref.watch(assetsActionProvider(scope.source));
  final assetIds = assets.remote().map((asset) => asset.id).toList(growable: false);
  if (assetIds.isEmpty) {
    return null;
  }

  final userId = ref.watch(currentUserProvider)?.id;
  final ownsSelectedAssets = userId != null && assets.owned(userId).length == assets.length;
  return scope.ownsAlbum || ownsSelectedAssets ? assetIds : null;
}, dependencies: [assetsActionProvider]);

class MoveToAlbumAction extends AssetActionBuilder {
  final String albumId;
  final bool ownsAlbum;

  const MoveToAlbumAction({required super.source, required this.albumId, required this.ownsAlbum});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final assetIds = ref.watch(_stateProvider((source: source, ownsAlbum: ownsAlbum)));
    if (assetIds == null) {
      return null;
    }

    return .new(
      icon: Icons.drive_file_move_outline,
      label: context.t.move_to_album,
      onAction: () => _move(context, ref, assetIds),
    );
  }

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

  Future<void> _move(BuildContext context, WidgetRef ref, List<String> assetIds) async {
    final targetAlbum = await _pickTargetAlbum(context);
    if (targetAlbum == null || !context.mounted) {
      return;
    }

    final translations = context.t;
    final albumNotifier = ref.read(remoteAlbumProvider.notifier);
    final toastService = ref.read(toastServiceProvider);
    final clearSelection = ref.read(clearSelectionProvider(source));

    final List<String> movedIds;
    try {
      movedIds = await albumNotifier.moveAssets(
        sourceAlbumId: albumId,
        targetAlbumId: targetAlbum.id,
        assetIds: assetIds,
      );
    } catch (_) {
      toastService.error(translations.errors.error_moving_assets_to_album);
      return;
    }

    final notMovedCount = assetIds.length - movedIds.length;
    final movedMessage = translations.assets_moved_to_album_count(count: movedIds.length);
    final notMovedMessage = translations.assets_cannot_be_moved_to_album_count(count: notMovedCount);

    if (movedIds.isEmpty) {
      toastService.error(notMovedMessage);
      return;
    }

    clearSelection();
    toastService.success(notMovedCount > 0 ? '$movedMessage\n$notMovedMessage' : movedMessage);
  }
}
