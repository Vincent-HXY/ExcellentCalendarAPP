import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_calendar_adapter.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/native_method_channel_contract.dart';
import 'package:excellent_calendar/gateway_interfaces/calendar_gateway.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_contract_enums.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_request_dtos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/calendar_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('excellent_calendar/calendar-test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses exact method names and frozen payloads', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final arguments = Map<String, dynamic>.from(call.arguments! as Map);
          final data = switch (call.method) {
            NativeCalendarMethods.rangeSummary => calendarRangeJson(
              CalendarRangeSummaryRequestDto(
                rangeStartDate: arguments['range_start_date']! as String,
                rangeEndDate: arguments['range_end_date']! as String,
                timezone: arguments['timezone']! as String,
              ),
            ),
            NativeCalendarMethods.listDayItems => calendarPageJson(
              CalendarListDayItemsRequestDto(
                date: arguments['date']! as String,
                timezone: arguments['timezone']! as String,
                section: CalendarSection.fromWireValue(
                  arguments['section']! as String,
                ),
                snapshotToken: arguments['snapshot_token']! as String,
                cursor: arguments['cursor'] as String?,
                pageSize: arguments['page_size']! as int,
              ),
            ),
            _ => throw StateError('unexpected method'),
          };
          return _success(data);
        });
    final adapter = MethodChannelCalendarAdapter(channel: channel);
    final rangeRequest = CalendarRangeSummaryRequestDto(
      rangeStartDate: '2026-08-31',
      rangeEndDate: '2026-09-07',
      timezone: calendarTimezone,
    );
    final pageRequest = CalendarListDayItemsRequestDto(
      date: '2026-08-31',
      timezone: calendarTimezone,
      section: CalendarSection.event,
      snapshotToken: calendarSnapshotA,
    );

    final range = await adapter.rangeSummary(rangeRequest);
    final page = await adapter.listDayItems(pageRequest);

    expect(range.days, hasLength(7));
    expect(page.items, hasLength(1));
    expect(calls.map((call) => call.method), [
      'calendar.range_summary',
      'calendar.list_day_items',
    ]);
    expect(calls[0].arguments, rangeRequest.toJson());
    expect(calls[1].arguments, pageRequest.toJson());
  });

  test(
    'maps a native snapshot-expired failure without losing details',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => {
              'ok': false,
              'data': null,
              'error': {
                'code': 'CALENDAR_SNAPSHOT_EXPIRED',
                'message': 'expired',
                'details': {'reason': 'write'},
                'retryable': true,
              },
              'contract_version': 2,
              'request_id': 'calendar-error',
            },
          );
      final adapter = MethodChannelCalendarAdapter(channel: channel);

      await expectLater(
        adapter.rangeSummary(
          CalendarRangeSummaryRequestDto(
            rangeStartDate: '2026-08-31',
            rangeEndDate: '2026-09-07',
            timezone: calendarTimezone,
          ),
        ),
        throwsA(
          isA<CalendarGatewayFailure>()
              .having(
                (error) => error.code,
                'code',
                'CALENDAR_SNAPSHOT_EXPIRED',
              )
              .having((error) => error.retryable, 'retryable', isTrue)
              .having((error) => error.details, 'details', {'reason': 'write'}),
        ),
      );
    },
  );

  test(
    'turns malformed or request-mismatched native data into contract failure',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final request = CalendarRangeSummaryRequestDto(
              rangeStartDate: '2026-08-31',
              rangeEndDate: '2026-09-07',
              timezone: calendarTimezone,
            );
            final data = calendarRangeJson(request)..['timezone'] = 'UTC';
            return _success(data);
          });
      final adapter = MethodChannelCalendarAdapter(channel: channel);

      await expectLater(
        adapter.rangeSummary(
          CalendarRangeSummaryRequestDto(
            rangeStartDate: '2026-08-31',
            rangeEndDate: '2026-09-07',
            timezone: calendarTimezone,
          ),
        ),
        throwsA(
          isA<CalendarGatewayFailure>().having(
            (error) => error.code,
            'code',
            'CONTRACT_VALIDATION_FAILED',
          ),
        ),
      );
    },
  );

  test('turns PlatformException into a typed local native failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(
            code: 'bridge_down',
            message: 'unavailable',
          ),
        );
    final adapter = MethodChannelCalendarAdapter(channel: channel);

    await expectLater(
      adapter.rangeSummary(
        CalendarRangeSummaryRequestDto(
          rangeStartDate: '2026-08-31',
          rangeEndDate: '2026-09-07',
          timezone: calendarTimezone,
        ),
      ),
      throwsA(
        isA<CalendarGatewayFailure>()
            .having((error) => error.code, 'code', 'NATIVE_INTERNAL_ERROR')
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
  });
}

Map<String, Object?> _success(Object data) => {
  'ok': true,
  'data': data,
  'error': null,
  'contract_version': 2,
  'request_id': 'calendar-test',
};
