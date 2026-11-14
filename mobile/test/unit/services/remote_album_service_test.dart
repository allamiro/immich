import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/services/remote_album.service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openapi/api.dart' show ApiException;

import '../../service.mocks.dart';
import '../mocks.dart';

void main() {
  late RemoteAlbumService sut;
  final mocks = RepositoryMocks();

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    sut = RemoteAlbumService(mocks.remoteAlbum, mocks.albumApi, MockForegroundUploadService());
  });

  tearDown(() {
    mocks.resetAll();
  });

  group('RemoteAlbumService', () {
    group('removeAssets', () {
      test('persists only the assets the server actually removed, not the whole request', () async {
        const albumId = 'album-1';
        const requested = ['asset-1', 'asset-2', 'asset-3'];
        const removed = ['asset-1', 'asset-3'];

        // The server rejected 'asset-2'
        when(
          () => mocks.albumApi.removeAssets(albumId, requested),
        ).thenAnswer((_) async => (removed: removed, failed: ['asset-2']));
        when(() => mocks.remoteAlbum.removeAssets(albumId, any())).thenAnswer((_) async {});

        final count = await sut.removeAssets(albumId: albumId, assetIds: requested);

        final persisted =
            verify(() => mocks.remoteAlbum.removeAssets(albumId, captureAny())).captured.single as List<String>;
        expect(persisted, removed);
        expect(persisted, isNot(contains('asset-2')));

        expect(count, removed.length);
      });
    });

    group('moveAssets', () {
      const sourceAlbumId = 'source-album';
      const targetAlbumId = 'target-album';

      setUp(() {
        when(() => mocks.remoteAlbum.moveAssets(any(), any(), any())).thenAnswer((_) async {});
      });

      test('moves every asset locally when the server moves all of them', () async {
        when(
          () => mocks.albumApi.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2']),
        ).thenAnswer((_) async => (moved: ['asset-1', 'asset-2'], failed: <String>[]));

        final movedIds = await sut.moveAssets(
          sourceAlbumId: sourceAlbumId,
          targetAlbumId: targetAlbumId,
          assetIds: ['asset-1', 'asset-2'],
        );

        expect(movedIds, ['asset-1', 'asset-2']);
        verify(() => mocks.albumApi.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2'])).called(1);
        verify(() => mocks.remoteAlbum.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2'])).called(1);
      });

      test('moves only the assets the server reports as moved', () async {
        when(
          () => mocks.albumApi.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2', 'asset-3']),
        ).thenAnswer((_) async => (moved: ['asset-1'], failed: ['asset-2', 'asset-3']));

        final movedIds = await sut.moveAssets(
          sourceAlbumId: sourceAlbumId,
          targetAlbumId: targetAlbumId,
          assetIds: ['asset-1', 'asset-2', 'asset-3'],
        );

        expect(movedIds, ['asset-1']);
        verify(() => mocks.remoteAlbum.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1'])).called(1);
        verifyNoMoreInteractions(mocks.remoteAlbum);
      });

      test('leaves the local albums untouched when the server moves nothing', () async {
        when(
          () => mocks.albumApi.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2']),
        ).thenAnswer((_) async => (moved: <String>[], failed: ['asset-1', 'asset-2']));

        final movedIds = await sut.moveAssets(
          sourceAlbumId: sourceAlbumId,
          targetAlbumId: targetAlbumId,
          assetIds: ['asset-1', 'asset-2'],
        );

        expect(movedIds, isEmpty);
        verifyNever(() => mocks.remoteAlbum.moveAssets(any(), any(), any()));
      });

      test('returns nothing and leaves the local albums untouched when the request fails', () async {
        when(
          () => mocks.albumApi.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2']),
        ).thenThrow(ApiException(400, 'Bad Request'));

        await expectLater(
          sut.moveAssets(sourceAlbumId: sourceAlbumId, targetAlbumId: targetAlbumId, assetIds: ['asset-1', 'asset-2']),
          throwsA(isA<ApiException>()),
        );

        verifyNever(() => mocks.remoteAlbum.moveAssets(any(), any(), any()));
      });
    });
  });
}
