import 'package:flutter/services.dart';

import '../../gateway_interfaces/calendar_gateway.dart';
import '../../native_contract/calendar/calendar_mapper.dart';
import '../../native_contract/calendar/calendar_request_dtos.dart';
import '../../native_contract/calendar/calendar_response_dtos.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelCalendarAdapter implements CalendarGateway {
  MethodChannelCalendarAdapter({MethodChannel? channel})
    : _invoker = NativeMethodChannelInvoker(
        channel ?? const MethodChannel(NativeMethodChannelNames.native),
      );

  final NativeMethodChannelInvoker _invoker;

  @override
  Future<CalendarRangeSummaryResponseDto> rangeSummary(
    CalendarRangeSummaryRequestDto request,
  ) async {
    final invocation = await _invoker.invoke<CalendarRangeSummaryResponseDto>(
      method: NativeCalendarMethods.rangeSummary,
      arguments: request.toJson(),
      parseData: (raw) {
        final response = CalendarMapper.rangeSummary(raw);
        response.validateAgainst(request);
        return response;
      },
    );
    return _unwrap(invocation);
  }

  @override
  Future<CalendarDayItemPageDto> listDayItems(
    CalendarListDayItemsRequestDto request,
  ) async {
    final invocation = await _invoker.invoke<CalendarDayItemPageDto>(
      method: NativeCalendarMethods.listDayItems,
      arguments: request.toJson(),
      parseData: (raw) {
        final response = CalendarMapper.dayItemPage(raw);
        response.validateAgainst(request);
        return response;
      },
    );
    return _unwrap(invocation);
  }

  T _unwrap<T>(NativeInvocation<T> invocation) {
    final data = invocation.result.data;
    if (invocation.result.ok && data != null) return data;
    final error = invocation.result.error;
    throw CalendarGatewayFailure(
      code: error?.code ?? 'NATIVE_INTERNAL_ERROR',
      message: error?.message ?? 'Calendar native invocation failed.',
      retryable: error?.retryable ?? false,
      details: error?.details,
    );
  }
}
