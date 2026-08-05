import 'package:excellent_calendar/gateway_interfaces/timezone_native_gateway.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/device_timezone_response_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/native_contract/runtime/localize_instants_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/resolve_local_datetime_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

typedef ResolveTimezoneFake =
    ResolveLocalDateTimeResponseDto Function(
      ResolveLocalDateTimeRequestDto request,
    );
typedef LocalizeTimezoneFake =
    List<LocalWallDateTime> Function(LocalizeInstantsRequestDto request);

class FakeTimezoneGateway implements TimezoneNativeGateway {
  FakeTimezoneGateway({
    List<String> deviceTimezones = const ['Asia/Shanghai'],
    ResolveTimezoneFake? resolve,
    LocalizeTimezoneFake? localize,
  }) : _deviceTimezones = List.of(deviceTimezones),
       _resolve = resolve,
       _localize = localize;

  final List<String> _deviceTimezones;
  final ResolveTimezoneFake? _resolve;
  final LocalizeTimezoneFake? _localize;
  int _deviceReadIndex = 0;

  final List<ResolveLocalDateTimeRequestDto> resolveRequests = [];
  final List<LocalizeInstantsRequestDto> localizeRequests = [];

  @override
  Future<NativeInvocation<DeviceTimezoneResponseDto>>
  getDeviceTimezone() async {
    final index = _deviceReadIndex < _deviceTimezones.length
        ? _deviceReadIndex
        : _deviceTimezones.length - 1;
    _deviceReadIndex += 1;
    return _success(
      DeviceTimezoneResponseDto(timezone: _deviceTimezones[index]),
    );
  }

  @override
  Future<NativeInvocation<ResolveLocalDateTimeResponseDto>>
  resolveLocalDateTime(ResolveLocalDateTimeRequestDto request) async {
    resolveRequests.add(request);
    final response =
        _resolve?.call(request) ??
        ResolveLocalDateTimeResponseDto(
          requestedLocalDateTime: request.localDateTime,
          resolvedLocalDateTime: request.localDateTime,
          utcInstant: DateTime.parse('${request.localDateTime}Z').toUtc(),
          timezone: request.timezone,
          resolution: LocalDateTimeResolution.exact,
        );
    return _success(response);
  }

  @override
  Future<NativeInvocation<LocalizeInstantsResponseDto>> localizeInstants(
    LocalizeInstantsRequestDto request,
  ) async {
    localizeRequests.add(request);
    final localized =
        _localize?.call(request) ??
        request.instants
            .map((instant) => LocalWallDateTime.fromDateTimeComponents(instant))
            .toList(growable: false);
    return _success(
      LocalizeInstantsResponseDto(
        timezone: request.timezone,
        items: List.generate(
          request.instants.length,
          (index) => LocalizedInstantDto(
            instant: request.instants[index],
            localDateTime: localized[index],
          ),
          growable: false,
        ),
      ),
    );
  }

  NativeInvocation<T> _success<T>(T data) {
    return NativeInvocation<T>(
      rawResponse: const {},
      result: NativeResultDto<T>(
        ok: true,
        data: data,
        error: null,
        contractVersion: 2,
        requestId: 'fake-timezone-request',
      ),
      isNativeResult: true,
    );
  }
}
