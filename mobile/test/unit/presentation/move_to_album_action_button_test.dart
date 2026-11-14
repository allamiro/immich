import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/config/album_config.dart';
import 'package:immich_mobile/domain/models/config/app_config.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/domain/services/asset.service.dart';
import 'package:immich_mobile/domain/services/remote_album.service.dart';
import 'package:immich_mobile/domain/services/user.service.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/move_to_album_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/album/album_tile.dart';
import 'package:immich_mobile/providers/album/album_sort_by_options.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openapi/api.dart' show ApiException;

import '../../infrastructure/repository.mock.dart';
import '../../utils.dart';
import '../presentation_context.dart';

class MockForegroundUploadService extends Mock implements ForegroundUploadService {}

class MockUserService extends Mock implements UserService {}

class MockAssetService extends Mock implements AssetService {}

RemoteAlbum _album({required String name, required String ownerId}) {
  return RemoteAlbum(
    id: TestUtils.uuid(),
    name: name,
    ownerId: ownerId,
    description: '',
    createdAt: TestUtils.yesterday(),
    updatedAt: TestUtils.now(),
    isActivityEnabled: false,
    order: AlbumAssetOrder.desc,
    assetCount: 0,
    ownerName: 'owner',
    isShared: false,
  );
}

RemoteAsset _asset({required String ownerId}) {
  final id = TestUtils.uuid();
  return RemoteAsset(
    id: id,
    name: 'remote_$id.jpg',
    ownerId: ownerId,
    checksum: TestUtils.uuid(),
    type: AssetType.image,
    createdAt: TestUtils.yesterday(),
    updatedAt: TestUtils.now(),
    isEdited: false,
  );
}

void main() {
  late PresentationContext context;
  late MockRemoteAlbumRepository remoteAlbumRepository;
  late MockDriftAlbumApiRepository albumApiRepository;
  late MockUserService userService;
  late MockAssetService assetService;

  late UserDto user;
  late RemoteAlbum sourceAlbum;
  late RemoteAlbum targetAlbum;
  late List<RemoteAsset> selectedAssets;
  late List<String> selectedIds;

  setUpAll(() {
    registerFallbackValue(_album(name: 'fallback', ownerId: 'fallback'));
    registerFallbackValue(
      UserDto(id: 'fallback', email: 'fallback@test.com', name: 'fallback', profileChangedAt: DateTime(2024)),
    );
  });

  setUp(() async {
    context = await PresentationContext.create();
    remoteAlbumRepository = MockRemoteAlbumRepository();
    albumApiRepository = MockDriftAlbumApiRepository();
    userService = MockUserService();
    assetService = MockAssetService();

    user = UserDto(id: TestUtils.uuid(), email: 'user@test.com', name: 'user', profileChangedAt: TestUtils.now());
    sourceAlbum = _album(name: 'Source album', ownerId: user.id);
    targetAlbum = _album(name: 'Target album', ownerId: user.id);
    selectedAssets = [_asset(ownerId: user.id), _asset(ownerId: user.id)];
    selectedIds = selectedAssets.map((asset) => asset.id).toList();

    when(() => userService.tryGetMyUser()).thenReturn(user);
    when(() => userService.watchMyUser()).thenAnswer((_) => const Stream.empty());
    when(() => assetService.getRemoteAsset(any())).thenAnswer((_) async => null);
    when(() => remoteAlbumRepository.getAll()).thenAnswer((_) async => [sourceAlbum, targetAlbum]);
    when(() => remoteAlbumRepository.get(any())).thenAnswer((_) async => null);
    when(() => remoteAlbumRepository.moveAssets(any(), any(), any())).thenAnswer((_) async {});
    when(() => remoteAlbumRepository.create(any(), any())).thenAnswer((_) async {});
  });

  tearDown(() async => await context.dispose());

  Future<void> pumpButton(WidgetTester tester) {
    return tester.pumpTestWidget(
      Center(child: MoveToAlbumActionButton(albumId: sourceAlbum.id)),
      overrides: [
        remoteAlbumServiceProvider.overrideWithValue(
          RemoteAlbumService(remoteAlbumRepository, albumApiRepository, MockForegroundUploadService()),
        ),
        currentUserProvider.overrideWith((ref) => CurrentUserProvider(userService)),
        assetServiceProvider.overrideWithValue(assetService),
        appConfigProvider.overrideWithValue(
          defaultConfig.copyWith(album: const AlbumConfig(sortMode: AlbumSortMode.title, isReverse: false)),
        ),
        multiSelectProvider.overrideWith(
          () => MultiSelectNotifier(
            MultiSelectState(selectedAssets: selectedAssets.toSet(), lockedSelectionAssets: const {}),
          ),
        ),
      ],
    );
  }

  Set<BaseAsset> selectionOf(WidgetTester tester) {
    final container = ProviderScope.containerOf(tester.element(find.byType(MoveToAlbumActionButton)));
    return container.read(multiSelectProvider).selectedAssets;
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byType(MoveToAlbumActionButton));
    await tester.pumpAndSettle();
  }

  Future<void> pickTargetAlbum(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(AlbumTile, targetAlbum.name));
    await tester.pumpAndSettle();
  }

  Future<void> dismissToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
  }

  void stubMove({required List<String> moved, required List<String> failed}) {
    when(
      () => albumApiRepository.moveAssets(sourceAlbum.id, targetAlbum.id, selectedIds),
    ).thenAnswer((_) async => (moved: moved, failed: failed));
  }

  group('MoveToAlbumActionButton', () {
    testWidgets('is labelled move to album', (tester) async {
      await pumpButton(tester);

      expect(find.text('Move to album'), findsOneWidget);
      expect(find.byIcon(Icons.drive_file_move_outline), findsOneWidget);
    });

    testWidgets('opens the album picker without the source album', (tester) async {
      await pumpButton(tester);

      await openPicker(tester);

      expect(find.text('Move to album'), findsNWidgets(2));
      expect(find.text('Create new album'), findsOneWidget);
      expect(find.widgetWithText(AlbumTile, targetAlbum.name), findsOneWidget);
      expect(find.widgetWithText(AlbumTile, sourceAlbum.name), findsNothing);
    });

    testWidgets('moves nothing when the picker is dismissed', (tester) async {
      await pumpButton(tester);
      await openPicker(tester);

      Navigator.of(tester.element(find.byType(AlbumTile))).pop();
      await tester.pumpAndSettle();

      verifyNever(() => albumApiRepository.moveAssets(any(), any(), any()));
      expect(selectionOf(tester), selectedAssets.toSet());
    });

    testWidgets('moves the selected assets with one request and clears the selection', (tester) async {
      stubMove(moved: selectedIds, failed: []);
      await pumpButton(tester);
      await openPicker(tester);

      await pickTargetAlbum(tester);

      verify(() => albumApiRepository.moveAssets(sourceAlbum.id, targetAlbum.id, selectedIds)).called(1);
      verify(() => remoteAlbumRepository.moveAssets(sourceAlbum.id, targetAlbum.id, selectedIds)).called(1);
      expect(find.byType(AlbumTile), findsNothing);
      expect(find.text('Moved 2 assets to the album'), findsOneWidget);
      expect(selectionOf(tester), isEmpty);

      await dismissToast(tester);
    });

    testWidgets('reports the moved count and the assets that could not be moved', (tester) async {
      stubMove(moved: [selectedIds.first], failed: [selectedIds.last]);
      await pumpButton(tester);
      await openPicker(tester);

      await pickTargetAlbum(tester);

      verify(() => remoteAlbumRepository.moveAssets(sourceAlbum.id, targetAlbum.id, [selectedIds.first])).called(1);
      expect(find.text('Moved 1 asset to the album\nCould not move 1 asset to the album'), findsOneWidget);
      expect(selectionOf(tester), isEmpty);

      await dismissToast(tester);
    });

    testWidgets('keeps the selection when no asset could be moved', (tester) async {
      stubMove(moved: [], failed: selectedIds);
      await pumpButton(tester);
      await openPicker(tester);

      await pickTargetAlbum(tester);

      verifyNever(() => remoteAlbumRepository.moveAssets(any(), any(), any()));
      expect(find.text('Could not move 2 assets to the album'), findsOneWidget);
      expect(selectionOf(tester), selectedAssets.toSet());

      await dismissToast(tester);
    });

    testWidgets('keeps the selection and shows one error when the request fails', (tester) async {
      when(
        () => albumApiRepository.moveAssets(sourceAlbum.id, targetAlbum.id, selectedIds),
      ).thenThrow(ApiException(400, 'Bad Request'));
      await pumpButton(tester);
      await openPicker(tester);

      await pickTargetAlbum(tester);

      verifyNever(() => remoteAlbumRepository.moveAssets(any(), any(), any()));
      expect(find.text('Error moving assets to album'), findsOneWidget);
      expect(find.textContaining('Moved'), findsNothing);
      expect(selectionOf(tester), selectedAssets.toSet());

      await dismissToast(tester);
    });

    testWidgets('moves the selected assets to an album created from the picker', (tester) async {
      final newAlbum = _album(name: 'New album', ownerId: user.id);
      when(
        () => albumApiRepository.createDriftAlbum('New album', user, assetIds: <String>[]),
      ).thenAnswer((_) async => newAlbum);
      when(
        () => albumApiRepository.moveAssets(sourceAlbum.id, newAlbum.id, selectedIds),
      ).thenAnswer((_) async => (moved: selectedIds, failed: <String>[]));
      await pumpButton(tester);
      await openPicker(tester);

      await tester.tap(find.text('Create new album'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'New album');
      await tester.tap(find.text('Create album'));
      await tester.pumpAndSettle();

      verify(() => albumApiRepository.createDriftAlbum('New album', user, assetIds: <String>[])).called(1);
      verify(() => albumApiRepository.moveAssets(sourceAlbum.id, newAlbum.id, selectedIds)).called(1);
      expect(find.text('Moved 2 assets to the album'), findsOneWidget);
      expect(selectionOf(tester), isEmpty);

      await dismissToast(tester);
    });
  });
}
