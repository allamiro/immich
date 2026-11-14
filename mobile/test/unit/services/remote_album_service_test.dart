import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/services/remote_album.service.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openapi/api.dart' show ApiException;

import '../../infrastructure/repository.mock.dart';

class MockForegroundUploadService extends Mock implements ForegroundUploadService {}

void main() {
  late RemoteAlbumService sut;
  late MockRemoteAlbumRepository remoteAlbumRepository;
  late MockDriftAlbumApiRepository albumApiRepository;

  setUp(() {
    remoteAlbumRepository = MockRemoteAlbumRepository();
    albumApiRepository = MockDriftAlbumApiRepository();
    sut = RemoteAlbumService(remoteAlbumRepository, albumApiRepository, MockForegroundUploadService());

    when(() => remoteAlbumRepository.moveAssets(any(), any(), any())).thenAnswer((_) async {});
  });

  group('moveAssets', () {
    const sourceAlbumId = 'source-album';
    const targetAlbumId = 'target-album';

    test('moves every asset locally when the server moves all of them', () async {
      when(
        () => albumApiRepository.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2']),
      ).thenAnswer((_) async => (moved: ['asset-1', 'asset-2'], failed: <String>[]));

      final movedIds = await sut.moveAssets(
        sourceAlbumId: sourceAlbumId,
        targetAlbumId: targetAlbumId,
        assetIds: ['asset-1', 'asset-2'],
      );

      expect(movedIds, ['asset-1', 'asset-2']);
      verify(() => albumApiRepository.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2'])).called(1);
      verify(() => remoteAlbumRepository.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2'])).called(1);
    });

    test('moves only the assets the server reports as moved', () async {
      when(
        () => albumApiRepository.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2', 'asset-3']),
      ).thenAnswer((_) async => (moved: ['asset-1'], failed: ['asset-2', 'asset-3']));

      final movedIds = await sut.moveAssets(
        sourceAlbumId: sourceAlbumId,
        targetAlbumId: targetAlbumId,
        assetIds: ['asset-1', 'asset-2', 'asset-3'],
      );

      expect(movedIds, ['asset-1']);
      verify(() => remoteAlbumRepository.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1'])).called(1);
      verifyNoMoreInteractions(remoteAlbumRepository);
    });

    test('leaves the local albums untouched when the server moves nothing', () async {
      when(
        () => albumApiRepository.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2']),
      ).thenAnswer((_) async => (moved: <String>[], failed: ['asset-1', 'asset-2']));

      final movedIds = await sut.moveAssets(
        sourceAlbumId: sourceAlbumId,
        targetAlbumId: targetAlbumId,
        assetIds: ['asset-1', 'asset-2'],
      );

      expect(movedIds, isEmpty);
      verifyNever(() => remoteAlbumRepository.moveAssets(any(), any(), any()));
    });

    test('returns nothing and leaves the local albums untouched when the request fails', () async {
      when(
        () => albumApiRepository.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2']),
      ).thenThrow(ApiException(400, 'Bad Request'));

      await expectLater(
        sut.moveAssets(sourceAlbumId: sourceAlbumId, targetAlbumId: targetAlbumId, assetIds: ['asset-1', 'asset-2']),
        throwsA(isA<ApiException>()),
      );

      verifyNever(() => remoteAlbumRepository.moveAssets(any(), any(), any()));
    });
  });
}
