import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_anniversary_adapter.dart';
import 'package:excellent_calendar/native_contract/anniversary/anniversary_contract_enums.dart';
import 'package:excellent_calendar/native_contract/anniversary/anniversary_request_dtos.dart';
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
    'all eight Anniversary methods use exact names and Contract payloads',
    () async {
      final captured = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured.add(call);
            return _success(switch (call.method) {
              'anniversary.create' ||
              'anniversary.update' ||
              'anniversary.set_reminders_enabled' => _mutation(),
              'anniversary.detail' => _detailView(),
              'anniversary.delete' => _deleteOperation(),
              'anniversary.list' => _list(),
              'anniversary.list_occurrences' => _occurrencePage(),
              'anniversary.preview_countdown' => _countdown(),
              _ => throw MissingPluginException(call.method),
            });
          });

      final adapter = MethodChannelAnniversaryAdapter(channel: channel);
      final create = await adapter.createAnniversary(
        CreateAnniversaryRequestDto(
          title: 'Project anniversary',
          date: DateTime(2020, 2, 29),
          calendarType: AnniversaryCalendarTypeContract.solar,
          categoryId: _categoryId,
          recurrence: const AnniversaryRecurrenceRuleInputDto.yearly(),
          note: null,
          importance: AnniversaryImportanceContract.importantNotUrgent,
          timezone: 'Asia/Shanghai',
          reminderPlan: AnniversaryReminderPlanInputDto(
            remindersEnabled: true,
            templates: const [
              AnniversaryReminderTemplateInputDto(
                advanceDays: 7,
                localTime: '09:00',
                isEnabled: true,
              ),
            ],
          ),
        ),
      );
      final update = await adapter.updateAnniversary(
        UpdateAnniversaryRequestDto(
          id: _anniversaryId,
          expectedUpdatedAt: DateTime.utc(2026, 8, 8, 2, 3, 4),
          title: 'Updated',
          date: DateTime(2021, 3, 1),
          calendarType: AnniversaryCalendarTypeContract.lunar,
          categoryId: null,
          recurrence: null,
          note: 'note',
          importance: AnniversaryImportanceContract.unimportantUrgent,
          timezone: 'Asia/Shanghai',
          reminderPlan: AnniversaryReminderPlanInputDto(
            remindersEnabled: false,
            templates: const [],
          ),
        ),
      );
      final deleted = await adapter.deleteAnniversary(
        const DeleteAnniversaryRequestDto(_anniversaryId),
      );
      final detail = await adapter.getAnniversaryDetail(
        const GetAnniversaryDetailRequestDto(
          id: _anniversaryId,
          timezone: 'Asia/Shanghai',
        ),
      );
      final list = await adapter.listAnniversaries(
        const ListAnniversariesRequestDto(
          timezone: 'Asia/Shanghai',
          categoryIds: [_categoryId],
          importance: [AnniversaryImportanceContract.importantNotUrgent],
          pagination: AnniversaryPaginationRequestDto(
            page: 2,
            pageSize: 50,
            cursor: null,
          ),
          sortBy: AnniversarySortByContract.countdownDays,
          sortDirection: AnniversarySortDirectionContract.descending,
        ),
      );
      final preview = await adapter.previewAnniversaryCountdown(
        PreviewAnniversaryCountdownRequestDto(
          date: DateTime(2020, 2, 29),
          calendarType: AnniversaryCalendarTypeContract.solar,
          recurrence: const AnniversaryRecurrenceRuleInputDto.yearly(),
          timezone: 'Asia/Shanghai',
        ),
      );
      final toggle = await adapter.setAnniversaryRemindersEnabled(
        const SetAnniversaryRemindersEnabledRequestDto(
          id: _anniversaryId,
          remindersEnabled: false,
          timezone: 'Asia/Shanghai',
        ),
      );
      final occurrences = await adapter.listAnniversaryOccurrences(
        ListAnniversaryOccurrencesRequestDto(
          rangeStartDate: DateTime(2026, 1, 1),
          rangeEndDate: DateTime(2027, 1, 1),
          timezone: 'Asia/Shanghai',
          categoryIds: const [],
          importance: const [],
          cursor: null,
          pageSize: 200,
        ),
      );

      expect(captured.map((call) => call.method), [
        'anniversary.create',
        'anniversary.update',
        'anniversary.delete',
        'anniversary.detail',
        'anniversary.list',
        'anniversary.preview_countdown',
        'anniversary.set_reminders_enabled',
        'anniversary.list_occurrences',
      ]);
      expect(captured[0].arguments, {
        'title': 'Project anniversary',
        'date': '2020-02-29',
        'calendar_type': 'solar',
        'category_id': _categoryId,
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
      expect(captured[1].arguments, {
        'id': _anniversaryId,
        'expected_updated_at': '2026-08-08T02:03:04Z',
        'title': 'Updated',
        'date': '2021-03-01',
        'calendar_type': 'lunar',
        'category_id': null,
        'recurrence': null,
        'note': 'note',
        'importance': 'unimportant_urgent',
        'timezone': 'Asia/Shanghai',
        'reminder_plan': {'reminders_enabled': false, 'templates': <Object?>[]},
      });
      expect(captured[2].arguments, {'id': _anniversaryId});
      expect(captured[3].arguments, {
        'id': _anniversaryId,
        'timezone': 'Asia/Shanghai',
      });
      expect(captured[4].arguments, {
        'timezone': 'Asia/Shanghai',
        'category_ids': [_categoryId],
        'importance': ['important_noturgent'],
        'pagination': {'page': 2, 'page_size': 50, 'cursor': null},
        'sort_by': 'countdown_days',
        'sort_direction': 'desc',
      });
      expect(captured[5].arguments, {
        'date': '2020-02-29',
        'calendar_type': 'solar',
        'recurrence': {'frequency': 'yearly', 'interval': 1},
        'timezone': 'Asia/Shanghai',
      });
      expect(captured[6].arguments, {
        'id': _anniversaryId,
        'reminders_enabled': false,
        'timezone': 'Asia/Shanghai',
      });
      expect(captured[7].arguments, {
        'range_start_date': '2026-01-01',
        'range_end_date': '2027-01-01',
        'timezone': 'Asia/Shanghai',
        'category_ids': <Object?>[],
        'importance': <Object?>[],
        'cursor': null,
        'page_size': 200,
      });
      expect(create.result.data!.detail.recurrence!.frequency, 'yearly');
      expect(update.result.ok, isTrue);
      expect(deleted.result.data!.anniversary.deletedAt, isNotNull);
      expect(detail.result.data!.detail.countdown.days, 203);
      expect(list.result.data!.pagination.hasMore, isFalse);
      expect(preview.result.data!.isoWeekday, 7);
      expect(
        toggle.result.data!.capability.scheduleReconciliationRequired,
        isFalse,
      );
      expect(occurrences.result.data!.items.single.reminderCount, 1);
    },
  );

  test('Anniversary pagination cannot serialize nested sort fields', () {
    expect(const AnniversaryPaginationRequestDto().toJson(), {
      'page': 1,
      'page_size': 20,
      'cursor': null,
    });
  });

  test(
    'business and Contract errors remain native NativeResult failures',
    () async {
      for (final code in [
        'ANNIVERSARY_NOT_FOUND',
        'ANNIVERSARY_CALENDAR_UNSUPPORTED',
        'CONTRACT_VALIDATION_FAILED',
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => _failure(code));

        final invocation =
            await MethodChannelAnniversaryAdapter(
              channel: channel,
            ).getAnniversaryDetail(
              const GetAnniversaryDetailRequestDto(
                id: _anniversaryId,
                timezone: 'Asia/Shanghai',
              ),
            );

        expect(invocation.isNativeResult, isTrue);
        expect(invocation.result.ok, isFalse);
        expect(invocation.result.error!.code, code);
      }
    },
  );

  test('malformed success becomes a local Contract boundary failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => _success({'anniversary': _anniversary()}),
        );

    final invocation = await MethodChannelAnniversaryAdapter(channel: channel)
        .getAnniversaryDetail(
          const GetAnniversaryDetailRequestDto(
            id: _anniversaryId,
            timezone: 'Asia/Shanghai',
          ),
        );

    expect(invocation.isNativeResult, isFalse);
    expect(invocation.result.error!.code, 'CONTRACT_VALIDATION_FAILED');
  });
}

const _anniversaryId = '11111111-1111-4111-8111-111111111111';
const _recurrenceId = '22222222-2222-4222-8222-222222222222';
const _categoryId = '33333333-3333-4333-8333-333333333333';

Map<String, Object?> _success(Object? data) => {
  'ok': true,
  'data': data,
  'error': null,
  'contract_version': 2,
  'request_id': 'anniversary-test',
};

Map<String, Object?> _failure(String code) => {
  'ok': false,
  'data': null,
  'error': {
    'code': code,
    'message': 'Anniversary failure',
    'details': {'source': 'test'},
    'retryable': false,
  },
  'contract_version': 2,
  'request_id': 'anniversary-failure',
};

Map<String, Object?> _anniversary({bool deleted = false}) => {
  'id': _anniversaryId,
  'title': 'Project anniversary',
  'date': '2020-02-29',
  'calendar_type': 'solar',
  'category_id': _categoryId,
  'recurrence_id': _recurrenceId,
  'note': null,
  'importance': 'important_noturgent',
  'created_at': '2026-08-08T01:02:03Z',
  'updated_at': '2026-08-08T02:03:04Z',
  'deleted_at': deleted ? '2026-08-08T03:04:05Z' : null,
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

Map<String, Object?> _capability() => {
  'schedule_status': 'scheduled_exact',
  'schedule_reconciliation_required': false,
  'notification_permission_status': 'granted',
  'exact_alarm_permission_status': 'granted',
  'degradation_reasons': <Object?>[],
};

Map<String, Object?> _mutation() => {
  'data_saved': true,
  'detail': _detail(),
  'capability': _capability(),
};

Map<String, Object?> _detailView() => {
  'detail': _detail(),
  'capability': _capability(),
};

Map<String, Object?> _deleteOperation() => {
  'data_saved': true,
  'commit': {
    'anniversary': _anniversary(deleted: true),
    'schedule_reconciliation_required': false,
  },
  'capability': _capability(),
};

Map<String, Object?> _occurrencePage() => {
  'items': [
    {
      'anniversary_id': _anniversaryId,
      'occurrence_key': '55555555-5555-5555-8555-555555555555',
      'occurrence_date': '2026-02-28',
      'source_date': '2020-02-29',
      'title': 'Project anniversary',
      'calendar_type': 'solar',
      'is_repeating': true,
      'years_elapsed': 6,
      'category_id': _categoryId,
      'importance': 'important_noturgent',
      'has_active_reminders': true,
      'reminder_count': 1,
    },
  ],
  'has_more': false,
  'next_cursor': null,
};

Map<String, Object?> _list() => {
  'items': [
    {'anniversary': _anniversary(), 'countdown': _countdown()},
  ],
  'pagination': {
    'total': 1,
    'page': 1,
    'page_size': 20,
    'has_more': false,
    'next_cursor': null,
  },
};
