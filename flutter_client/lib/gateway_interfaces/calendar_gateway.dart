import '../native_contract/calendar/calendar_request_dtos.dart';
import '../native_contract/calendar/calendar_response_dtos.dart';

abstract interface class CalendarGateway {
  Future<CalendarRangeSummaryResponseDto> rangeSummary(
    CalendarRangeSummaryRequestDto request,
  );

  Future<CalendarDayItemPageDto> listDayItems(
    CalendarListDayItemsRequestDto request,
  );
}

class CalendarGatewayFailure implements Exception {
  const CalendarGatewayFailure({
    required this.code,
    required this.message,
    required this.retryable,
    this.details,
  });

  final String code;
  final String message;
  final bool retryable;
  final Map<String, dynamic>? details;

  bool get isSnapshotExpired => code == 'CALENDAR_SNAPSHOT_EXPIRED';

  @override
  String toString() => 'CalendarGatewayFailure($code, $message)';
}
