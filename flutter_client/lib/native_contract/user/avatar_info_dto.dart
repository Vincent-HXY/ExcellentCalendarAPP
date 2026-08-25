import '../shared/contract_value.dart';

/// Public avatar metadata. Object-storage keys are never exposed.
class AvatarInfoDto {
  const AvatarInfoDto({
    required this.assetId,
    required this.url,
    required this.thumbnailUrl,
    required this.etag,
    required this.updatedAt,
  });

  final String assetId;
  final String url;
  final String thumbnailUrl;
  final String etag;
  final DateTime updatedAt;

  factory AvatarInfoDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'asset_id',
      'url',
      'thumbnail_url',
      'etag',
      'updated_at',
    }, 'AvatarInfo');

    final url = json['url'];
    final thumbnailUrl = json['thumbnail_url'];
    final etag = json['etag'];
    if (url is! String || url.isEmpty || url.length > 2048) {
      throw const FormatException('AvatarInfo.url must be a 1..2048 string.');
    }
    if (thumbnailUrl is! String ||
        thumbnailUrl.isEmpty ||
        thumbnailUrl.length > 2048) {
      throw const FormatException(
        'AvatarInfo.thumbnail_url must be a 1..2048 string.',
      );
    }
    if (etag is! String || etag.isEmpty || etag.length > 256) {
      throw const FormatException('AvatarInfo.etag must be a 1..256 string.');
    }
    return AvatarInfoDto(
      assetId: ContractValue.uuid(json, 'asset_id', 'AvatarInfo'),
      url: url,
      thumbnailUrl: thumbnailUrl,
      etag: etag,
      updatedAt: ContractValue.utcDateTime(json, 'updated_at', 'AvatarInfo'),
    );
  }

  Map<String, dynamic> toJson() => {
    'asset_id': assetId,
    'url': url,
    'thumbnail_url': thumbnailUrl,
    'etag': etag,
    'updated_at': ContractValue.formatUtcDateTime(
      updatedAt,
      field: 'AvatarInfo.updated_at',
    ),
  };
}
