import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/constants/errors.dart';
import 'package:immich_mobile/repositories/drift_album_api_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openapi/api.dart';

import '../../api.mocks.dart';

BulkIdResponseDto _moved(String id) => BulkIdResponseDto(id: id, success: true);

BulkIdResponseDto _notMoved(String id, BulkIdErrorReason reason) =>
    BulkIdResponseDto(id: id, success: false, error: Optional.present(reason));

void main() {
  late DriftAlbumApiRepository sut;
  late MockAlbumsApi albumsApi;

  setUp(() {
    albumsApi = MockAlbumsApi();
    sut = DriftAlbumApiRepository(albumsApi);
  });

  group('moveAssets', () {
    const sourceAlbumId = 'source-album';
    const targetAlbumId = 'target-album';

    AlbumMoveAssetsDto requestFor(List<String> assetIds) =>
        AlbumMoveAssetsDto(targetAlbumId: targetAlbumId, assetIds: assetIds);

    test('sends a single request to the source album with the target album and asset ids', () async {
      when(
        () => albumsApi.moveAssetsToAlbum(sourceAlbumId, requestFor(['asset-1', 'asset-2'])),
      ).thenAnswer((_) async => [_moved('asset-1'), _moved('asset-2')]);

      await sut.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2']);

      verify(() => albumsApi.moveAssetsToAlbum(sourceAlbumId, requestFor(['asset-1', 'asset-2']))).called(1);
      verifyNoMoreInteractions(albumsApi);
    });

    test('reports every asset as moved when the server moves all of them', () async {
      when(
        () => albumsApi.moveAssetsToAlbum(sourceAlbumId, requestFor(['asset-1', 'asset-2'])),
      ).thenAnswer((_) async => [_moved('asset-1'), _moved('asset-2')]);

      final result = await sut.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2']);

      expect(result.moved, ['asset-1', 'asset-2']);
      expect(result.failed, isEmpty);
    });

    test('separates moved assets from not found and no permission results', () async {
      when(() => albumsApi.moveAssetsToAlbum(sourceAlbumId, requestFor(['asset-1', 'asset-2', 'asset-3']))).thenAnswer(
        (_) async => [
          _moved('asset-1'),
          _notMoved('asset-2', BulkIdErrorReason.notFound),
          _notMoved('asset-3', BulkIdErrorReason.noPermission),
        ],
      );

      final result = await sut.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2', 'asset-3']);

      expect(result.moved, ['asset-1']);
      expect(result.failed, ['asset-2', 'asset-3']);
    });

    test('reports no moved assets when the server moves none of them', () async {
      when(() => albumsApi.moveAssetsToAlbum(sourceAlbumId, requestFor(['asset-1', 'asset-2']))).thenAnswer(
        (_) async => [
          _notMoved('asset-1', BulkIdErrorReason.noPermission),
          _notMoved('asset-2', BulkIdErrorReason.notFound),
        ],
      );

      final result = await sut.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1', 'asset-2']);

      expect(result.moved, isEmpty);
      expect(result.failed, ['asset-1', 'asset-2']);
    });

    test('propagates the error when the whole request is rejected', () async {
      when(
        () => albumsApi.moveAssetsToAlbum(sourceAlbumId, requestFor(['asset-1'])),
      ).thenThrow(ApiException(400, 'Bad Request'));

      await expectLater(
        sut.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1']),
        throwsA(isA<ApiException>().having((error) => error.code, 'code', 400)),
      );
    });

    test('throws when the server sends no response body', () async {
      when(() => albumsApi.moveAssetsToAlbum(sourceAlbumId, requestFor(['asset-1']))).thenAnswer((_) async => null);

      await expectLater(sut.moveAssets(sourceAlbumId, targetAlbumId, ['asset-1']), throwsA(isA<NoResponseDtoError>()));
    });
  });
}
