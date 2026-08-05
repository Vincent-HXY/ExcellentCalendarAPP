import '../shared/contract_value.dart';

class DeviceTimezoneResponseDto {
  const DeviceTimezoneResponseDto({required this.timezone});

  final String timezone;

  factory DeviceTimezoneResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'timezone',
    }, 'DeviceTimezoneResponse');
    final timezone = ContractValue.nonEmptyString(
      json,
      'timezone',
      'DeviceTimezoneResponse',
    );
    if (timezone.length > 255) {
      throw const FormatException(
        'DeviceTimezoneResponse.timezone is too long.',
      );
    }
    return DeviceTimezoneResponseDto(timezone: timezone);
  }
}
