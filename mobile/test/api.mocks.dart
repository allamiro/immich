import 'package:immich_mobile/repositories/partner_api.repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openapi/api.dart';

class MockAlbumsApi extends Mock implements AlbumsApi {}

class MockSyncApi extends Mock implements SyncApi {}

class MockServerApi extends Mock implements ServerApi {}

class MockPartnerApiRepository extends Mock implements PartnerApiRepository {}
