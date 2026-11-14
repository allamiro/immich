import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/config/album_config.dart';
import 'package:immich_mobile/domain/models/config/app_config.dart';
import 'package:immich_mobile/domain/services/remote_album.service.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/actions/action.widget.dart';
import 'package:immich_mobile/presentation/actions/move_to_album.action.dart';
import 'package:immich_mobile/presentation/widgets/album/album_tile.dart';
import 'package:immich_mobile/providers/album/album_sort_by_options.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openapi/api.dart' show ApiException;

import '../../../infrastructure/repository.mock.dart';
import '../../factories/local_asset_factory.dart';
import '../../factories/remote_album_factory.dart';
import '../../factories/remote_asset_factory.dart';
import '../presentation_context.dart';

void main() {
  final translations = StaticTranslations.instance;

  late PresentationContext context;
  late MockRemoteAlbumRepository remoteAlbumRepository;
  late MockAlbumApiRepository albumApiRepository;

  late RemoteAlbum sourceAlbum;
  late RemoteAlbum targetAlbum;
  late List<RemoteAsset> selectedAssets;
  late List<String> selectedIds;

  setUpAll(() {
    registerFallbackValue(RemoteAlbumFactory.create());
  });

  setUp(() async {
    context = await PresentationContext.create();
    remoteAlbumRepository = context.repository.remoteAlbum;
    albumApiRepository = context.repository.albumApi;

    final userId = context.currentUser.id;
    sourceAlbum = RemoteAlbumFactory.create(name: 'Source album', ownerId: userId);
    targetAlbum = RemoteAlbumFactory.create(name: 'Target album', ownerId: userId);
    selectedAssets = [RemoteAssetFactory.create(ownerId: userId), RemoteAssetFactory.create(ownerId: userId)];
    selectedIds = selectedAssets.map((asset) => asset.id).toList();

    when(() => context.service.asset.service.getRemoteAsset(any())).thenAnswer((_) async => null);
    when(() => remoteAlbumRepository.getAll()).thenAnswer((_) async => [sourceAlbum, targetAlbum]);
    when(() => remoteAlbumRepository.get(any())).thenAnswer((_) async => null);
    when(() => remoteAlbumRepository.moveAssets(any(), any(), any())).thenAnswer((_) async {});
    when(() => remoteAlbumRepository.create(any(), any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    context.repository.resetAll();
    await context.dispose();
  });

  Future<void> pumpAction(WidgetTester tester, {Set<BaseAsset>? selection, bool ownsAlbum = true}) {
    return tester.pumpTestWidget(
      context,
      Center(
        child: ActionColumnButton(
          action: MoveToAlbumAction(source: .timeline, albumId: sourceAlbum.id, ownsAlbum: ownsAlbum),
        ),
      ),
      overrides: [
        ...context.selected(selection ?? selectedAssets.toSet()),
        remoteAlbumServiceProvider.overrideWithValue(
          RemoteAlbumService(remoteAlbumRepository, albumApiRepository, context.service.upload),
        ),
        toastServiceProvider.overrideWithValue(context.service.toast),
        appConfigProvider.overrideWithValue(
          defaultConfig.copyWith(album: const AlbumConfig(sortMode: AlbumSortMode.title, isReverse: false)),
        ),
      ],
    );
  }

  Set<BaseAsset> selectionOf(WidgetTester tester) {
    final container = ProviderScope.containerOf(tester.element(find.byType(ActionColumnButton)));
    return container.read(multiSelectProvider).selectedAssets;
  }

  Future<void> pumpWhilePicking(WidgetTester tester) async {
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byType(ImmichColumnButton));
    await pumpWhilePicking(tester);
  }

  Future<void> pickTargetAlbum(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(AlbumTile, targetAlbum.name));
    await tester.pumpAndSettle();
  }

  void stubMove({required List<String> moved, required List<String> failed}) {
    when(
      () => albumApiRepository.moveAssets(sourceAlbum.id, targetAlbum.id, selectedIds),
    ).thenAnswer((_) async => (moved: moved, failed: failed));
  }

  String successToast() => verify(() => context.service.toast.success(captureAny())).captured.single as String;

  String errorToast() => verify(() => context.service.toast.error(captureAny())).captured.single as String;

  group('MoveToAlbumAction', () {
    testWidgets('is labelled move to album', (tester) async {
      await pumpAction(tester);

      expect(find.text(translations.move_to_album), findsOneWidget);
      expect(find.byIcon(Icons.drive_file_move_outline), findsOneWidget);
    });

    testWidgets('is shown for owned assets in an album of another user', (tester) async {
      await pumpAction(tester, ownsAlbum: false);

      expect(find.byType(ImmichColumnButton), findsOneWidget);
    });

    testWidgets('is hidden when the user owns neither the album nor every selected asset', (tester) async {
      await pumpAction(tester, selection: {selectedAssets.first, RemoteAssetFactory.create()}, ownsAlbum: false);

      expect(find.byType(ImmichColumnButton), findsNothing);
    });

    testWidgets('is hidden for a local-only asset', (tester) async {
      await pumpAction(tester, selection: {LocalAssetFactory.create()});

      expect(find.byType(ImmichColumnButton), findsNothing);
    });

    testWidgets('opens the album picker without the source album', (tester) async {
      await pumpAction(tester);

      await openPicker(tester);

      expect(find.text(translations.move_to_album), findsNWidgets(2));
      expect(find.text(translations.common_create_new_album), findsOneWidget);
      expect(find.widgetWithText(AlbumTile, targetAlbum.name), findsOneWidget);
      expect(find.widgetWithText(AlbumTile, sourceAlbum.name), findsNothing);
    });

    testWidgets('moves nothing when the picker is dismissed', (tester) async {
      await pumpAction(tester);
      await openPicker(tester);

      Navigator.of(tester.element(find.byType(AlbumTile))).pop();
      await tester.pumpAndSettle();

      verifyNever(() => albumApiRepository.moveAssets(any(), any(), any()));
      expect(selectionOf(tester), selectedAssets.toSet());
    });

    testWidgets('moves the selected assets with one request and clears the selection', (tester) async {
      stubMove(moved: selectedIds, failed: []);
      await pumpAction(tester);
      await openPicker(tester);

      await pickTargetAlbum(tester);

      verify(() => albumApiRepository.moveAssets(sourceAlbum.id, targetAlbum.id, selectedIds)).called(1);
      verify(() => remoteAlbumRepository.moveAssets(sourceAlbum.id, targetAlbum.id, selectedIds)).called(1);
      expect(find.byType(AlbumTile), findsNothing);
      expect(successToast(), translations.assets_moved_to_album_count(count: 2));
      verifyNever(() => context.service.toast.error(any()));
      expect(selectionOf(tester), isEmpty);
    });

    testWidgets('reports the moved count and the assets that could not be moved', (tester) async {
      stubMove(moved: [selectedIds.first], failed: [selectedIds.last]);
      await pumpAction(tester);
      await openPicker(tester);

      await pickTargetAlbum(tester);

      verify(() => remoteAlbumRepository.moveAssets(sourceAlbum.id, targetAlbum.id, [selectedIds.first])).called(1);
      expect(
        successToast(),
        '${translations.assets_moved_to_album_count(count: 1)}\n'
        '${translations.assets_cannot_be_moved_to_album_count(count: 1)}',
      );
      expect(selectionOf(tester), isEmpty);
    });

    testWidgets('keeps the selection when no asset could be moved', (tester) async {
      stubMove(moved: [], failed: selectedIds);
      await pumpAction(tester);
      await openPicker(tester);

      await pickTargetAlbum(tester);

      verifyNever(() => remoteAlbumRepository.moveAssets(any(), any(), any()));
      expect(errorToast(), translations.assets_cannot_be_moved_to_album_count(count: 2));
      verifyNever(() => context.service.toast.success(any()));
      expect(selectionOf(tester), selectedAssets.toSet());
    });

    testWidgets('keeps the selection and shows one error when the request fails', (tester) async {
      when(
        () => albumApiRepository.moveAssets(sourceAlbum.id, targetAlbum.id, selectedIds),
      ).thenThrow(ApiException(400, 'Bad Request'));
      await pumpAction(tester);
      await openPicker(tester);

      await pickTargetAlbum(tester);

      verifyNever(() => remoteAlbumRepository.moveAssets(any(), any(), any()));
      expect(errorToast(), translations.errors.error_moving_assets_to_album);
      verifyNever(() => context.service.toast.success(any()));
      expect(selectionOf(tester), selectedAssets.toSet());
    });

    testWidgets('moves the selected assets to an album created from the picker', (tester) async {
      final newAlbum = RemoteAlbumFactory.create(name: 'New album', ownerId: context.currentUser.id);
      when(
        () => albumApiRepository.createDriftAlbum('New album', context.currentUser, assetIds: <String>[]),
      ).thenAnswer((_) async => newAlbum);
      when(
        () => albumApiRepository.moveAssets(sourceAlbum.id, newAlbum.id, selectedIds),
      ).thenAnswer((_) async => (moved: selectedIds, failed: <String>[]));
      await pumpAction(tester);
      await openPicker(tester);

      await tester.tap(find.text(translations.common_create_new_album));
      await pumpWhilePicking(tester);
      await tester.enterText(find.byType(TextFormField), 'New album');
      await tester.tap(find.text(translations.create_album));
      await tester.pumpAndSettle();

      verify(
        () => albumApiRepository.createDriftAlbum('New album', context.currentUser, assetIds: <String>[]),
      ).called(1);
      verify(() => albumApiRepository.moveAssets(sourceAlbum.id, newAlbum.id, selectedIds)).called(1);
      expect(successToast(), translations.assets_moved_to_album_count(count: 2));
      expect(selectionOf(tester), isEmpty);
    });
  });
}
