import '../../gateway_interfaces/timezone_native_gateway.dart';
import '../../native_contract/event/event_occurrence_response_dto.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/runtime/device_timezone_response_dto.dart';
import '../../native_contract/runtime/local_wall_date_time.dart';
import '../../native_contract/runtime/localize_instants_dto.dart';
import '../../native_contract/runtime/resolve_local_datetime_dto.dart';
import '../../native_contract/shared/native_invocation.dart';

class LocalizedTimeRange {
  const LocalizedTimeRange({
    required this.start,
    required this.end,
    required this.timezone,
  });

  final LocalWallDateTime start;
  final LocalWallDateTime end;
  final String timezone;
}

class LocalizedTimeRangesResult {
  const LocalizedTimeRangesResult._({
    required this.ok,
    required this.ranges,
    this.errorCode,
    this.errorMessage,
  });

  const LocalizedTimeRangesResult.success(
    Map<String, LocalizedTimeRange> ranges,
  ) : this._(ok: true, ranges: ranges);

  const LocalizedTimeRangesResult.failure({
    required String? errorCode,
    required String? errorMessage,
  }) : this._(
         ok: false,
         ranges: const {},
         errorCode: errorCode,
         errorMessage: errorMessage,
       );

  final bool ok;
  final Map<String, LocalizedTimeRange> ranges;
  final String? errorCode;
  final String? errorMessage;
}

class TimezoneApplicationService {
  const TimezoneApplicationService(this._gateway);

  final TimezoneNativeGateway _gateway;

  Future<NativeInvocation<DeviceTimezoneResponseDto>> getDeviceTimezone() {
    return _gateway.getDeviceTimezone();
  }

  Future<NativeInvocation<ResolveLocalDateTimeResponseDto>>
  resolveLocalDateTime({
    required LocalWallDateTime localDateTime,
    required String timezone,
  }) {
    return _gateway.resolveLocalDateTime(
      ResolveLocalDateTimeRequestDto(
        localDateTime: localDateTime,
        timezone: timezone,
      ),
    );
  }

  Future<NativeInvocation<LocalizeInstantsResponseDto>> localizeInstants({
    required String timezone,
    required List<DateTime> instants,
  }) {
    return _gateway.localizeInstants(
      LocalizeInstantsRequestDto(timezone: timezone, instants: instants),
    );
  }

  Future<LocalizedTimeRangesResult> localizeEventTimes(
    Iterable<EventResponseDto> events,
  ) {
    return _localizeRanges(
      events.map(
        (event) => event.isAllDay
            ? _TimeRangeInput.allDay(
                key: event.id,
                startDate: event.startDate!,
                endDate: event.endDate!,
                timezone: event.timezone,
              )
            : _TimeRangeInput.timed(
                key: event.id,
                startAt: event.startAt!,
                endAt: event.endAt!,
                timezone: event.timezone,
              ),
      ),
    );
  }

  Future<LocalizedTimeRangesResult> localizeOccurrenceTimes(
    Iterable<EventOccurrenceResponseDto> occurrences,
  ) {
    return _localizeRanges(
      occurrences.map(
        (occurrence) => occurrence.occurrenceStartAt == null
            ? _TimeRangeInput.allDay(
                key: occurrence.occurrenceKey,
                startDate: occurrence.occurrenceStartDate!,
                endDate: occurrence.occurrenceEndDate!,
                timezone: occurrence.timezone,
              )
            : _TimeRangeInput.timed(
                key: occurrence.occurrenceKey,
                startAt: occurrence.occurrenceStartAt!,
                endAt: occurrence.occurrenceEndAt!,
                timezone: occurrence.timezone,
              ),
      ),
    );
  }

  Future<LocalizedTimeRangesResult> _localizeRanges(
    Iterable<_TimeRangeInput> inputs,
  ) async {
    final ranges = <String, LocalizedTimeRange>{};
    final timedByTimezone = <String, List<_TimeRangeInput>>{};
    for (final input in inputs) {
      if (input.startDate != null) {
        ranges[input.key] = LocalizedTimeRange(
          start: LocalWallDateTime.fromLocalDate(input.startDate!),
          end: LocalWallDateTime.fromLocalDate(input.endDate!),
          timezone: input.timezone,
        );
      } else {
        timedByTimezone.putIfAbsent(input.timezone, () => []).add(input);
      }
    }

    for (final entry in timedByTimezone.entries) {
      final groupedInputs = entry.value;
      for (var offset = 0; offset < groupedInputs.length; offset += 200) {
        final end = offset + 200 < groupedInputs.length
            ? offset + 200
            : groupedInputs.length;
        final chunk = groupedInputs.sublist(offset, end);
        final instants = <DateTime>[
          for (final input in chunk) ...[input.startAt!, input.endAt!],
        ];
        final invocation = await localizeInstants(
          timezone: entry.key,
          instants: instants,
        );
        if (!invocation.result.ok) {
          return LocalizedTimeRangesResult.failure(
            errorCode: invocation.result.error?.code,
            errorMessage: invocation.result.error?.message,
          );
        }
        final items = invocation.result.data!.items;
        for (var index = 0; index < chunk.length; index++) {
          ranges[chunk[index].key] = LocalizedTimeRange(
            start: items[index * 2].localDateTime,
            end: items[index * 2 + 1].localDateTime,
            timezone: entry.key,
          );
        }
      }
    }
    return LocalizedTimeRangesResult.success(Map.unmodifiable(ranges));
  }
}

class _TimeRangeInput {
  const _TimeRangeInput.timed({
    required this.key,
    required DateTime this.startAt,
    required DateTime this.endAt,
    required this.timezone,
  }) : startDate = null,
       endDate = null;

  const _TimeRangeInput.allDay({
    required this.key,
    required String this.startDate,
    required String this.endDate,
    required this.timezone,
  }) : startAt = null,
       endAt = null;

  final String key;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? startDate;
  final String? endDate;
  final String timezone;
}
