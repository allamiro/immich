//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class AlbumMoveAssetsDto {
  /// Returns a new [AlbumMoveAssetsDto] instance.
  AlbumMoveAssetsDto({
    this.assetIds = const [],
    required this.targetAlbumId,
  });

  /// Asset IDs
  List<String> assetIds;

  /// Target album ID
  String targetAlbumId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is AlbumMoveAssetsDto &&
    _deepEquality.equals(other.assetIds, assetIds) &&
    other.targetAlbumId == targetAlbumId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (assetIds.hashCode) +
    (targetAlbumId.hashCode);

  @override
  String toString() => 'AlbumMoveAssetsDto[assetIds=$assetIds, targetAlbumId=$targetAlbumId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'assetIds'] = this.assetIds;
      json[r'targetAlbumId'] = this.targetAlbumId;
    return json;
  }

  /// Returns a new [AlbumMoveAssetsDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AlbumMoveAssetsDto? fromJson(dynamic value) {
    upgradeDto(value, "AlbumMoveAssetsDto");
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      return AlbumMoveAssetsDto(
        assetIds: json[r'assetIds'] is Iterable
            ? (json[r'assetIds'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        targetAlbumId: mapValueOfType<String>(json, r'targetAlbumId')!,
      );
    }
    return null;
  }

  static List<AlbumMoveAssetsDto> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <AlbumMoveAssetsDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AlbumMoveAssetsDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AlbumMoveAssetsDto> mapFromJson(dynamic json) {
    final map = <String, AlbumMoveAssetsDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AlbumMoveAssetsDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AlbumMoveAssetsDto-objects as value to a dart map
  static Map<String, List<AlbumMoveAssetsDto>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<AlbumMoveAssetsDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AlbumMoveAssetsDto.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'assetIds',
    'targetAlbumId',
  };
}

