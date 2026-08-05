import '../shared/contract_value.dart';
import 'local_wall_date_time.dart';

enum LocalDateTimeResolution {
  exact('exact'),
  gapShifted('gap_shifted'),
  foldEarlier('fold_earlier');

  const LocalDateTimeResolution(this.wireValue);

  final String wireValue;

  static LocalDateTimeResolution parse(String value) {
    return values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () =>
          throw FormatException('Unknown LocalDateTimeResolution: $value'),
    );
  }
}

class ResolveLocalDateTimeRequestDto {
  const ResolveLocalDateTimeRequestDto({
    required this.localDateTime,
    required this.timezone,
  });

  final LocalWallDateTime localDateTime;
  final String timezone;

  Map<String, dynamic> toJson() {
    if (timezone.isEmpty || timezone.length > 255) {
      throw const FormatException(
        'ResolveLocalDateTimeRequest.timezone is invalid.',
      );
    }
    return {'local_datetime': localDateTime.toString(), 'timezone': timezone};
  }
}

class ResolveLocalDateTimeResponseDto {
  const ResolveLocalDateTimeResponseDto({
    required this.requestedLocalDateTime,
    required this.resolvedLocalDateTime,
    required this.utcInstant,
    required this.timezone,
    required this.resolution,
  });

  static const _keys = {
    'requested_local_datetime',
    'resolved_local_datetime',
    'utc_instant',
    'timezone',
    'resolution',
  };

  final LocalWallDateTime requestedLocalDateTime;
  final LocalWallDateTime resolvedLocalDateTime;
  final DateTime utcInstant;
  final String timezone;
  final LocalDateTimeResolution resolution;

  factory ResolveLocalDateTimeResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, _keys, 'ResolveLocalDateTimeResponse');
    final requested = LocalWallDateTime.parse(
      ContractValue.nonEmptyString(
        json,
        'requested_local_datetime',
        'ResolveLocalDateTimeResponse',
      ),
    );
    final resolved = LocalWallDateTime.parse(
      ContractValue.nonEmptyString(
        json,
        'resolved_local_datetime',
        'ResolveLocalDateTimeResponse',
      ),
    );
    final resolution = LocalDateTimeResolution.parse(
      ContractValue.nonEmptyString(
        json,
        'resolution',
        'ResolveLocalDateTimeResponse',
      ),
    );
    if (resolution == LocalDateTimeResolution.gapShifted) {
      if (!requested.isBefore(resolved)) {
        throw const FormatException(
          'gap_shifted must move to a later legal local date-time.',
        );
      }
    } else if (requested != resolved) {
      throw const FormatException(
        'Non-gap resolution must preserve the requested local date-time.',
      );
    }
    final timezone = ContractValue.nonEmptyString(
      json,
      'timezone',
      'ResolveLocalDateTimeResponse',
    );
    if (timezone.length > 255) {
      throw const FormatException(
        'ResolveLocalDateTimeResponse.timezone is too long.',
      );
    }
    return ResolveLocalDateTimeResponseDto(
      requestedLocalDateTime: requested,
      resolvedLocalDateTime: resolved,
      utcInstant: ContractValue.utcDateTime(
        json,
        'utc_instant',
        'ResolveLocalDateTimeResponse',
        wholeSecond: true,
      ),
      timezone: timezone,
      resolution: resolution,
    );
  }
}
