import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/event_detail_response_dto.dart';
import '../../native_contract/event/event_occurrence_response_dto.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/event/get_event_detail_request_dto.dart';
import '../../native_contract/event/list_event_occurrences_request_dto.dart';
import '../../native_contract/runtime/local_wall_date_time.dart';
import '../timezone/timezone_application_service.dart';
import 'recurring_event_detail_models.dart';

class RecurringEventDetailLoadData {
  const RecurringEventDetailLoadData({
    required this.detail,
    required this.localizedEventTimeRange,
    required this.referenceLocalNow,
    required this.occurrences,
    required this.hasMore,
    required this.nextCursor,
    required this.query,
  });

  final EventDetailResponseDto detail;
  final LocalizedTimeRange localizedEventTimeRange;
  final LocalWallDateTime referenceLocalNow;
  final List<RecurringEventOccurrenceItem> occurrences;
  final bool hasMore;
  final String? nextCursor;
  final RecurringOccurrenceQuery? query;
}

class RecurringEventOccurrencePage {
  const RecurringEventOccurrencePage({
    required this.occurrences,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<RecurringEventOccurrenceItem> occurrences;
  final bool hasMore;
  final String? nextCursor;
}

class RecurringEventDetailLoader {
  RecurringEventDetailLoader({
    required String eventId,
    required EventNativeGateway gateway,
    required TimezoneApplicationService timezoneService,
    DateTime Function()? clock,
    Duration pastExtent = const Duration(days: 7),
    Duration futureExtent = const Duration(days: 90),
    this.pageSize = 100,
  }) : _eventId = eventId,
       _gateway = gateway,
       _timezoneService = timezoneService,
       _clock = clock ?? DateTime.now,
       _pastExtent = pastExtent,
       _futureExtent = futureExtent {
    if (eventId.trim().isEmpty) {
      throw ArgumentError.value(eventId, 'eventId', 'must be non-empty');
    }
    if (pastExtent.isNegative || futureExtent <= Duration.zero) {
      throw ArgumentError('Occurrence query extents are invalid.');
    }
    if (pageSize < 1 || pageSize > 200) {
      throw RangeError.range(pageSize, 1, 200, 'pageSize');
    }
  }

  final String _eventId;
  final EventNativeGateway _gateway;
  final TimezoneApplicationService _timezoneService;
  final DateTime Function() _clock;
  final Duration _pastExtent;
  final Duration _futureExtent;
  final int pageSize;

  Future<RecurringEventDetailLoadData> load() async {
    try {
      final nowUtc = _wholeSecondUtc(_clock());
      final detailInvocation = await _gateway.getEventDetail(
        GetEventDetailRequestDto(id: _eventId),
      );
      if (!detailInvocation.result.ok || detailInvocation.result.data == null) {
        throw _LoadFailure(
          RecurringEventFailure.fromNativeError(detailInvocation.result.error),
        );
      }
      final detail = detailInvocation.result.data!;
      if (detail.event.id != _eventId) {
        throw const _LoadFailure(
          RecurringEventFailure(message: 'Native 返回了其他日程的详情'),
        );
      }

      final localizedEvent = await _timezoneService.localizeEventTimes([
        detail.event,
      ]);
      final eventTimeRange = localizedEvent.ranges[detail.event.id];
      if (!localizedEvent.ok || eventTimeRange == null) {
        throw _LoadFailure(
          RecurringEventFailure(
            code: localizedEvent.errorCode,
            message: localizedEvent.errorMessage ?? '无法按日程原时区显示时间',
          ),
        );
      }

      final referenceNowInvocation = await _timezoneService.localizeInstants(
        timezone: detail.event.timezone,
        instants: [nowUtc],
      );
      if (!referenceNowInvocation.result.ok ||
          referenceNowInvocation.result.data == null) {
        throw _LoadFailure(
          RecurringEventFailure.fromNativeError(
            referenceNowInvocation.result.error,
          ),
        );
      }
      final localizedNow = referenceNowInvocation.result.data!;
      if (localizedNow.timezone != detail.event.timezone ||
          localizedNow.items.length != 1 ||
          !localizedNow.items.single.instant.isAtSameMomentAs(nowUtc)) {
        throw const _LoadFailure(
          RecurringEventFailure(message: 'Native 返回的原时区当前时间不一致'),
        );
      }
      final referenceLocalNow = localizedNow.items.single.localDateTime;

      if (detail.recurrence == null) {
        return RecurringEventDetailLoadData(
          detail: detail,
          localizedEventTimeRange: eventTimeRange,
          referenceLocalNow: referenceLocalNow,
          occurrences: const [],
          hasMore: false,
          nextCursor: null,
          query: null,
        );
      }

      final query = RecurringOccurrenceQuery.forEvent(
        detail.event,
        nowUtc: nowUtc,
        referenceLocalNow: referenceLocalNow,
        pastExtent: _pastExtent,
        futureExtent: _futureExtent,
      );
      final occurrencePage = await loadMore(
        query: query,
        detail: detail,
        cursor: null,
        localizationFailureMessage: '无法按日程原时区显示 occurrence',
        unexpectedFailureMessage: '加载日程详情失败，请稍后重试',
      );
      return RecurringEventDetailLoadData(
        detail: detail,
        localizedEventTimeRange: eventTimeRange,
        referenceLocalNow: referenceLocalNow,
        occurrences: occurrencePage.occurrences,
        hasMore: occurrencePage.hasMore,
        nextCursor: occurrencePage.nextCursor,
        query: query,
      );
    } on _LoadFailure {
      rethrow;
    } catch (_) {
      throw const _LoadFailure(
        RecurringEventFailure(message: '加载日程详情失败，请稍后重试'),
      );
    }
  }

  Future<RecurringEventOccurrencePage> loadMore({
    required RecurringOccurrenceQuery query,
    required EventDetailResponseDto detail,
    required String? cursor,
    String localizationFailureMessage = '无法按日程原时区显示更多日期',
    String unexpectedFailureMessage = '加载更多日程失败，请稍后重试',
  }) async {
    try {
      final invocation = await _gateway.listOccurrences(
        query.toRequest(cursor: cursor, limit: pageSize),
      );
      if (!invocation.result.ok || invocation.result.data == null) {
        throw _LoadFailure(
          RecurringEventFailure.fromNativeError(invocation.result.error),
        );
      }
      final response = invocation.result.data!;
      final projectionFailure = _validateOccurrences(
        response.items,
        detail: detail,
      );
      if (projectionFailure != null) {
        throw _LoadFailure(projectionFailure);
      }
      if (response.hasMore && response.nextCursor == null) {
        throw const _LoadFailure(
          RecurringEventFailure(message: 'Native 返回了无法继续分页的 occurrence 列表'),
        );
      }
      final localized = await _timezoneService.localizeOccurrenceTimes(
        response.items,
      );
      if (!localized.ok) {
        throw _LoadFailure(
          RecurringEventFailure(
            code: localized.errorCode,
            message: localized.errorMessage ?? localizationFailureMessage,
          ),
        );
      }
      final items = _buildOccurrenceItems(response.items, localized.ranges);
      return RecurringEventOccurrencePage(
        occurrences: items,
        hasMore: response.hasMore,
        nextCursor: response.nextCursor,
      );
    } on _LoadFailure {
      rethrow;
    } catch (_) {
      throw _LoadFailure(
        RecurringEventFailure(message: unexpectedFailureMessage),
      );
    }
  }

  static RecurringEventFailure? _validateOccurrences(
    List<EventOccurrenceResponseDto> occurrences, {
    required EventDetailResponseDto detail,
  }) {
    final recurrence = detail.recurrence!;
    final seen = <String>{};
    for (final occurrence in occurrences) {
      if (occurrence.eventId != detail.event.id ||
          occurrence.recurrenceRevision != recurrence.revision ||
          occurrence.timezone != detail.event.timezone ||
          !seen.add(occurrence.occurrenceKey)) {
        return const RecurringEventFailure(
          message: 'Native occurrence 投影与当前重复日程不一致',
        );
      }
    }
    return null;
  }

  static List<RecurringEventOccurrenceItem> _buildOccurrenceItems(
    List<EventOccurrenceResponseDto> occurrences,
    Map<String, LocalizedTimeRange> localizedRanges,
  ) {
    final items = <RecurringEventOccurrenceItem>[];
    for (final occurrence in occurrences) {
      final range = localizedRanges[occurrence.occurrenceKey];
      if (range == null || range.timezone != occurrence.timezone) {
        throw const _LoadFailure(
          RecurringEventFailure(message: 'occurrence 缺少原时区显示时间'),
        );
      }
      items.add(
        RecurringEventOccurrenceItem(
          occurrence: occurrence,
          localizedTimeRange: range,
        ),
      );
    }
    return List.unmodifiable(items);
  }

  static DateTime _wholeSecondUtc(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    );
  }
}

class RecurringOccurrenceQuery {
  const RecurringOccurrenceQuery.timed({
    required this.eventId,
    required this.recurrenceRevision,
    required this.rangeStartAt,
    required this.rangeEndAt,
  }) : rangeStartDate = null,
       rangeEndDate = null;

  const RecurringOccurrenceQuery.allDay({
    required this.eventId,
    required this.recurrenceRevision,
    required this.rangeStartDate,
    required this.rangeEndDate,
  }) : rangeStartAt = null,
       rangeEndAt = null;

  factory RecurringOccurrenceQuery.forEvent(
    EventResponseDto event, {
    required DateTime nowUtc,
    required LocalWallDateTime referenceLocalNow,
    required Duration pastExtent,
    required Duration futureExtent,
  }) {
    if (!event.isAllDay) {
      return RecurringOccurrenceQuery.timed(
        eventId: event.id,
        recurrenceRevision: event.recurrenceRevision!,
        rangeStartAt: RecurringEventDetailLoader._wholeSecondUtc(
          nowUtc.subtract(pastExtent),
        ),
        rangeEndAt: RecurringEventDetailLoader._wholeSecondUtc(
          nowUtc.add(futureExtent),
        ),
      );
    }
    final anchor = DateTime.utc(
      referenceLocalNow.year,
      referenceLocalNow.month,
      referenceLocalNow.day,
    );
    final start = anchor.subtract(Duration(days: _ceilDays(pastExtent)));
    final end = anchor.add(Duration(days: _ceilDays(futureExtent)));
    return RecurringOccurrenceQuery.allDay(
      eventId: event.id,
      recurrenceRevision: event.recurrenceRevision!,
      rangeStartDate: _formatLocalDate(start),
      rangeEndDate: _formatLocalDate(end),
    );
  }

  final String eventId;
  final int recurrenceRevision;
  final DateTime? rangeStartAt;
  final DateTime? rangeEndAt;
  final String? rangeStartDate;
  final String? rangeEndDate;

  ListEventOccurrencesRequestDto toRequest({
    String? cursor,
    required int limit,
  }) {
    if (rangeStartAt != null) {
      return ListEventOccurrencesRequestDto.timed(
        eventId: eventId,
        recurrenceRevision: recurrenceRevision,
        rangeStartAt: rangeStartAt!,
        rangeEndAt: rangeEndAt!,
        cursor: cursor,
        limit: limit,
      );
    }
    return ListEventOccurrencesRequestDto.allDay(
      eventId: eventId,
      recurrenceRevision: recurrenceRevision,
      rangeStartDate: rangeStartDate!,
      rangeEndDate: rangeEndDate!,
      cursor: cursor,
      limit: limit,
    );
  }

  static int _ceilDays(Duration duration) {
    if (duration == Duration.zero) return 0;
    const dayMicros = Duration.microsecondsPerDay;
    return (duration.inMicroseconds + dayMicros - 1) ~/ dayMicros;
  }

  static String _formatLocalDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

class RecurringEventDetailLoadException implements Exception {
  const RecurringEventDetailLoadException(this.failure);

  final RecurringEventFailure failure;
}

class _LoadFailure extends RecurringEventDetailLoadException {
  const _LoadFailure(super.failure);
}
