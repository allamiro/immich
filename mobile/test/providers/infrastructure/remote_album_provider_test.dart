import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/services/remote_album.service.dart';
import 'package:immich_mobile/infrastructure/repositories/remote_album.repository.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../infrastructure/repository.mock.dart';
import '../../medium/repository_context.dart';
import '../../service.mocks.dart';

void main() {
  late MediumRepositoryContext ctx;
  late MockAlbumApiRepository albumApiRepository;
  late ProviderContainer container;

  setUp(() {
    ctx = MediumRepositoryContext();
    albumApiRepository = MockAlbumApiRepository();
    container = ProviderContainer(
      overrides: [
        remoteAlbumServiceProvider.overrideWithValue(
          RemoteAlbumService(RemoteAlbumRepository(ctx.db), albumApiRepository, MockForegroundUploadService()),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await ctx.dispose();
  });

  RemoteAlbum albumInState(String albumId) =>
      container.read(remoteAlbumProvider).albums.singleWhere((album) => album.id == albumId);

  group('moveAssets', () {
    test('updates the asset counts of both albums in the state after a move', () async {
      final user = await ctx.newUser();
      final source = await ctx.newRemoteAlbum(ownerId: user.id);
      final target = await ctx.newRemoteAlbum(ownerId: user.id);
      final moved = await ctx.newRemoteAsset(ownerId: user.id);
      final kept = await ctx.newRemoteAsset(ownerId: user.id);
      await ctx.newRemoteAlbumAsset(albumId: source.id, assetId: moved.id);
      await ctx.newRemoteAlbumAsset(albumId: source.id, assetId: kept.id);
      when(
        () => albumApiRepository.moveAssets(source.id, target.id, [moved.id]),
      ).thenAnswer((_) async => (moved: [moved.id], failed: <String>[]));
      final notifier = container.read(remoteAlbumProvider.notifier);
      await notifier.refresh();

      final movedIds = await notifier.moveAssets(
        sourceAlbumId: source.id,
        targetAlbumId: target.id,
        assetIds: [moved.id],
      );

      expect(movedIds, [moved.id]);
      expect(albumInState(source.id).assetCount, 1);
      expect(albumInState(target.id).assetCount, 1);
      expect(albumInState(target.id).thumbnailAssetId, moved.id);
    });
  });
}
