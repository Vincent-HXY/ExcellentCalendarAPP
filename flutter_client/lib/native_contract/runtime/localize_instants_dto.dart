import '../shared/contract_value.dart';
import 'local_wall_date_time.dart';

class LocalizeInstantsRequestDto {
  const LocalizeInstantsRequestDto({
    required this.timezone,
    required this.instants,
  });

  static const maxBatchSize = 400;

  final String timezone;
  final List<DateTime> instants;

  List<String> get encodedInstants => instants
      .map(
        (instant) => ContractValue.formatUtcSecond(
          instant,
          field: 'LocalizeInstantsRequest.instants',
        ),
      )
      .toList(growable: false);

  Map<String, dynamic> toJson() {
    if (timezone.isEmpty || timezone.length > 255) {
      throw const FormatException(
        'LocalizeInstantsRequest.timezone is invalid.',
      );
    }
    if (instants.isEmpty || instants.length > maxBatchSize) {
      throw const FormatException(
        'LocalizeInstantsRequest.instants must contain 1 to 400 values.',
      );
    }
    if (instants.any((instant) => !instant.isUtc)) {
      throw const FormatException(
        'LocalizeInstantsRequest.instants must be UTC DateTime values.',
      );
    }
    return {'timezone': timezone, 'instants': encodedInstants};
  }
}

class LocalizedInstantDto {
  const LocalizedInstantDto({
    required this.instant,
    required this.localDateTime,
  });

  final DateTime instant;
  final LocalWallDateTime localDateTime;

  factory LocalizedInstantDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'instant',
      'local_datetime',
    }, 'LocalizedInstant');
    return LocalizedInstantDto(
      instant: ContractValue.utcDateTime(
        json,
        'instant',
        'LocalizedInstant',
        wholeSecond: true,
      ),
      localDateTime: LocalWallDateTime.parse(
        ContractValue.nonEmptyString(
          json,
          'local_datetime',
          'LocalizedInstant',
        ),
      ),
    );
  }
}

class LocalizeInstantsResponseDto {
  const LocalizeInstantsResponseDto({
    required this.timezone,
    required this.items,
  });

  final String timezone;
  final List<LocalizedInstantDto> items;

  factory LocalizeInstantsResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'timezone',
      'items',
    }, 'LocalizeInstantsResponse');
    final timezone = ContractValue.nonEmptyString(
      json,
      'timezone',
      'LocalizeInstantsResponse',
    );
    final rawItems = json['items'];
    if (timezone.length > 255 ||
        rawItems is! List ||
        rawItems.isEmpty ||
        rawItems.length > LocalizeInstantsRequestDto.maxBatchSize ||
        rawItems.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('LocalizeInstantsResponse is invalid.');
    }
    return LocalizeInstantsResponseDto(
      timezone: timezone,
      items: List<LocalizedInstantDto>.unmodifiable(
        rawItems.cast<Map<String, dynamic>>().map(LocalizedInstantDto.fromJson),
      ),
    );
  }
}
