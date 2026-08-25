import 'package:excellent_calendar/application/anniversary/anniversary_models.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_anniversary_adapter.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_timezone_adapter.dart';
import 'package:excellent_calendar/data/anniversary/native_anniversary_gateway.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('excellent_calendar/native');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'current Flutter gateway port reaches Anniversary MethodChannel',
    () async {
      final captured = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured.add(call);
            return switch (call.method) {
              'runtime.device_timezone' => _success({
                'timezone': 'Asia/Shanghai',
              }),
              'anniversary.create' => _success(_mutation()),
              _ => throw MissingPluginException(call.method),
            };
          });
      final gateway = _gateway(channel);

      final detail = await gateway.create(
        CreateAnniversaryPlan(
          anniversary: AnniversaryDraft(
            title: 'Project anniversary',
            date: DateTime(2020, 2, 29),
            calendarType: AnniversaryCalendarType.solar,
            categoryId: null,
            note: null,
            importance: AnniversaryImportance.importantNotUrgent,
          ),
          kind: AnniversaryKind.anniversary,
          recurrence: const RecurrenceDraft.yearly(),
          reminders: const [ReminderDraft(advanceDays: 7)],
          remindersEnabled: true,
        ),
      );

      expect(captured.map((call) => call.method), [
        'runtime.device_timezone',
        'anniversary.create',
      ]);
      expect(captured.last.arguments, {
        'title': 'Project anniversary',
        'date': '2020-02-29',
        'calendar_type': 'solar',
        'category_id': null,
        'recurrence': {'frequency': 'yearly', 'interval': 1},
        'note': null,
        'importance': 'important_noturgent',
        'timezone': 'Asia/Shanghai',
        'reminder_plan': {
          'reminders_enabled': true,
          'templates': [
            {
              'advance_days': 7,
              'local_time': '09:00',
              'method': 'popup',
              'is_enabled': true,
            },
          ],
        },
      });
      expect(detail.anniversary.id, _anniversaryId);
      expect(detail.kind, AnniversaryKind.anniversary);
      expect(detail.reminders.single.advanceDays, 7);
    },
  );

  test('list obtains IANA timezone then invokes anniversary.list', () async {
    final captured = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured.add(call);
          return switch (call.method) {
            'runtime.device_timezone' => _success({
              'timezone': 'Asia/Shanghai',
            }),
            'anniversary.list' => _success(
              _list(page: 2, total: 21, hasMore: false),
            ),
            _ => throw MissingPluginException(call.method),
          };
        });

    final result = await _gateway(
      channel,
    ).list(const AnniversaryListQuery(page: 2));

    expect(captured.map((call) => call.method), [
      'runtime.device_timezone',
      'anniversary.list',
    ]);
    expect(captured.last.arguments, {
      'timezone': 'Asia/Shanghai',
      'pagination': {'page': 2, 'page_size': 20, 'cursor': null},
    });
    expect(result.page, 2);
    expect(result.total, 21);
    expect(result.hasMore, isFalse);
    expect(result.items.single.countdown.days, 203);
    expect(result.items.single.countdown.weekdayLabel, '周日');
  });

  test('update obtains IANA timezone and sends it explicitly', () async {
    final captured = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured.add(call);
          return switch (call.method) {
            'runtime.device_timezone' => _success({
              'timezone': 'Asia/Shanghai',
            }),
            'anniversary.update' => _success(_mutation()),
            _ => throw MissingPluginException(call.method),
          };
        });

    await _gateway(channel).update(
      UpdateAnniversaryPlan(
        id: _anniversaryId,
        expectedUpdatedAt: DateTime.utc(2026, 8, 8, 2, 3, 4),
        anniversary: AnniversaryDraft(
          title: 'Updated anniversary',
          date: DateTime(2020, 2, 29),
          calendarType: AnniversaryCalendarType.solar,
          categoryId: null,
          note: null,
          importance: AnniversaryImportance.importantNotUrgent,
        ),
        kind: AnniversaryKind.anniversary,
        recurrence: const RecurrenceDraft.yearly(),
        reminders: const [],
      ),
    );

    expect(captured.map((call) => call.method), [
      'runtime.device_timezone',
      'anniversary.update',
    ]);
    expect(
      (captured.last.arguments as Map<Object?, Object?>)['timezone'],
      'Asia/Shanghai',
    );
    expect(
      (captured.last.arguments as Map<Object?, Object?>)['expected_updated_at'],
      '2026-08-08T02:03:04Z',
    );
  });

  test('stale update maps to a refresh-required conflict', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'runtime.device_timezone' => _success({
              'timezone': 'Asia/Shanghai',
            }),
            'anniversary.update' => _failure('ANNIVERSARY_UPDATE_CONFLICT'),
            _ => throw MissingPluginException(call.method),
          };
        });

    await expectLater(
      _gateway(channel).update(
        UpdateAnniversaryPlan(
          id: _anniversaryId,
          expectedUpdatedAt: DateTime.utc(2026, 8, 8, 2, 3, 4),
          anniversary: AnniversaryDraft(
            title: 'Stale edit',
            date: DateTime(2020, 2, 29),
            calendarType: AnniversaryCalendarType.solar,
            categoryId: null,
            note: null,
            importance: AnniversaryImportance.importantNotUrgent,
          ),
          kind: AnniversaryKind.anniversary,
          recurrence: const RecurrenceDraft.yearly(),
          reminders: const [],
        ),
      ),
      throwsA(
        isA<AnniversaryGatewayException>()
            .having(
              (error) => error.code,
              'code',
              AnniversaryFailureCode.updateConflict,
            )
            .having(
              anniversaryFailureMessage,
              'message',
              '纪念日已在其他页面被修改，请返回详情刷新后重试',
            ),
      ),
    );
  });

  test('unsupported prototype kind fails before transport', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          calls += 1;
          return _success(_mutation());
        });
    final gateway = _gateway(channel);
    final draft = AnniversaryDraft(
      title: 'Birthday',
      date: DateTime(2026, 8, 8),
      calendarType: AnniversaryCalendarType.solar,
      categoryId: null,
      note: null,
      importance: AnniversaryImportance.unimportantNotUrgent,
    );

    await expectLater(
      gateway.create(
        CreateAnniversaryPlan(
          anniversary: draft,
          kind: AnniversaryKind.birthday,
          recurrence: null,
          reminders: const [],
        ),
      ),
      throwsA(isA<AnniversaryGatewayException>()),
    );
    expect(calls, 0);
  });

  test(
    'preview sends recurrence through the production gateway port',
    () async {
      final captured = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured.add(call);
            return switch (call.method) {
              'runtime.device_timezone' => _success({
                'timezone': 'Asia/Shanghai',
              }),
              'anniversary.preview_countdown' => _success(_countdown()),
              _ => throw MissingPluginException(call.method),
            };
          });

      final result = await _gateway(channel).previewCountdown(
        AnniversaryDraft(
          title: 'Project anniversary',
          date: DateTime(2020, 2, 29),
          calendarType: AnniversaryCalendarType.solar,
          categoryId: null,
          note: null,
          importance: AnniversaryImportance.importantNotUrgent,
        ),
        recurrence: const RecurrenceDraft.yearly(),
      );

      expect(captured.map((call) => call.method), [
        'runtime.device_timezone',
        'anniversary.preview_countdown',
      ]);
      expect(captured.last.arguments, {
        'date': '2020-02-29',
        'calendar_type': 'solar',
        'recurrence': {'frequency': 'yearly', 'interval': 1},
        'timezone': 'Asia/Shanghai',
      });
      expect(result.days, 203);
    },
  );

  test(
    'native lunar rejection maps to the explicit user-facing failure',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'runtime.device_timezone' => _success({
                'timezone': 'Asia/Shanghai',
              }),
              'anniversary.preview_countdown' => _failure(
                'ANNIVERSARY_CALENDAR_UNSUPPORTED',
              ),
              _ => throw MissingPluginException(call.method),
            };
          });

      await expectLater(
        _gateway(channel).previewCountdown(
          AnniversaryDraft(
            title: '农历纪念日',
            date: DateTime(2026, 8, 20),
            calendarType: AnniversaryCalendarType.lunar,
            categoryId: null,
            note: null,
            importance: AnniversaryImportance.unimportantNotUrgent,
          ),
          recurrence: null,
        ),
        throwsA(
          isA<AnniversaryGatewayException>()
              .having(
                (error) => error.code,
                'code',
                AnniversaryFailureCode.calendarUnsupported,
              )
              .having(anniversaryFailureMessage, 'message', '当前版本暂不支持农历'),
        ),
      );
    },
  );
}

NativeAnniversaryGateway _gateway(MethodChannel channel) =>
    NativeAnniversaryGateway(
      nativeGateway: MethodChannelAnniversaryAdapter(channel: channel),
      timezoneGateway: MethodChannelTimezoneAdapter(channel: channel),
    );

const _anniversaryId = '11111111-1111-4111-8111-111111111111';
const _recurrenceId = '22222222-2222-4222-8222-222222222222';

Map<String, Object?> _success(Object? data) => {
  'ok': true,
  'data': data,
  'error': null,
  'contract_version': 2,
  'request_id': 'native-gateway-test',
};

Map<String, Object?> _failure(String code) => {
  'ok': false,
  'data': null,
  'error': {
    'code': code,
    'message': 'Anniversary failure',
    'details': <String, Object?>{},
    'retryable': false,
  },
  'contract_version': 2,
  'request_id': 'native-gateway-failure',
};

Map<String, Object?> _anniversary() => {
  'id': _anniversaryId,
  'title': 'Project anniversary',
  'date': '2020-02-29',
  'calendar_type': 'solar',
  'category_id': null,
  'recurrence_id': _recurrenceId,
  'note': null,
  'importance': 'important_noturgent',
  'created_at': '2026-08-08T01:02:03Z',
  'updated_at': '2026-08-08T02:03:04Z',
  'deleted_at': null,
};

Map<String, Object?> _countdown() => {
  'relation': 'remaining',
  'days': 203,
  'target_occurrence_date': '2027-02-28',
  'iso_weekday': 7,
  'timezone': 'Asia/Shanghai',
  'calculated_at': '2026-08-08T04:05:06Z',
};

Map<String, Object?> _detail() => {
  'anniversary': _anniversary(),
  'recurrence': {
    'recurrence_id': _recurrenceId,
    'frequency': 'yearly',
    'interval': 1,
  },
  'countdown': _countdown(),
  'reminder_settings': {
    'reminders_enabled': true,
    'templates': [
      {
        'template_key': '44444444-4444-5444-8444-444444444444',
        'advance_days': 7,
        'local_time': '09:00',
        'timezone_mode': 'follow_device',
        'method': 'popup',
        'is_enabled': true,
      },
    ],
    'active_reminder_count': 1,
    'schedule_reconciliation_required': false,
  },
};

Map<String, Object?> _mutation() => {
  'data_saved': true,
  'detail': _detail(),
  'capability': {
    'schedule_status': 'scheduled_exact',
    'schedule_reconciliation_required': false,
    'notification_permission_status': 'granted',
    'exact_alarm_permission_status': 'granted',
    'degradation_reasons': <Object?>[],
  },
};

Map<String, Object?> _list({
  int page = 1,
  int total = 1,
  bool hasMore = false,
}) => {
  'items': [
    {'anniversary': _anniversary(), 'countdown': _countdown()},
  ],
  'pagination': {
    'total': total,
    'page': page,
    'page_size': 20,
    'has_more': hasMore,
    'next_cursor': null,
  },
};
