import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_reminder_adapter.dart';
import 'package:excellent_calendar/native_contract/reminder/cancel_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/create_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/list_reminders_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_contract_enums.dart';
import 'package:excellent_calendar/native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/update_reminder_request_dto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/reminder_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('excellent_calendar/native');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // 目的：确认 Adapter 使用正式方法名和 Contract 字段；方法：拦截 MethodChannel 并检查 MethodCall。
  test('adapter invokes reminder.create with contract payload', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return reminderSuccessInvocation().rawResponse;
        });

    final adapter = MethodChannelReminderAdapter(channel: channel);
    final invocation = await adapter.createReminder(
      CreateReminderRequestDto(
        targetType: ReminderTargetType.event,
        targetId: 'event-1',
        remindAt: DateTime.utc(2026, 6, 15, 2),
        methods: const [ReminderMethod.popup],
        source: ReminderSource.manual,
      ),
    );

    expect(captured!.method, 'reminder.create');
    expect(captured!.arguments['target_id'], 'event-1');
    expect(captured!.arguments['methods'], ['popup']);
    expect(invocation.result.ok, isTrue);
  });

  // 目的：防止取消提醒的方法名漂移；方法：记录调用并精确比较 method 与 arguments。
  test('adapter invokes reminder.cancel instead of delete aliases', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return reminderSuccessInvocation(
            status: 'cancelled',
            isEnabled: false,
            deletedAt: '2026-06-15T03:00:00.000Z',
          ).rawResponse;
        });

    final adapter = MethodChannelReminderAdapter(channel: channel);
    await adapter.cancelReminder(
      const CancelReminderRequestDto(reminderId: 'reminder-1'),
    );

    expect(captured!.method, 'reminder.cancel');
    expect(captured!.arguments, {'reminder_id': 'reminder-1'});
  });

  // 目的：确认非 NativeResult 的平台返回不会被误判为成功；方法：返回坏数据并检查标准内部错误。
  test(
    'adapter converts PlatformException into transport invocation',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'bridge_unavailable');
          });

      final invocation = await MethodChannelReminderAdapter(channel: channel)
          .cancelReminder(
            const CancelReminderRequestDto(reminderId: 'reminder-1'),
          );

      expect(invocation.isNativeResult, isFalse);
      expect(invocation.result.error!.code, 'NATIVE_INTERNAL_ERROR');
      expect(invocation.result.error!.details!['method'], 'reminder.cancel');
    },
  );

  test('adapter invokes reminder.update with the V2 time shape', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return reminderSuccessInvocation().rawResponse;
        });

    await MethodChannelReminderAdapter(channel: channel).updateReminder(
      UpdateReminderRequestDto.useAdvanceMinutes(
        reminderId: 'reminder-1',
        value: 30,
      ),
    );

    expect(captured!.method, 'reminder.update');
    expect(captured!.arguments, {
      'reminder_id': 'reminder-1',
      'remind_at': null,
      'advance_minutes': 30,
    });
  });

  test('adapter invokes reminder.list with occurrence filters', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return {
            'ok': true,
            'data': {
              'items': [reminderResponseJson()],
              'pagination': {
                'total': 1,
                'page': 1,
                'page_size': 20,
                'has_more': false,
                'next_cursor': null,
              },
            },
            'error': null,
            'contract_version': 2,
            'request_id': 'list-1',
          };
        });

    final result = await MethodChannelReminderAdapter(channel: channel)
        .listReminders(
          const ListRemindersRequestDto(
            recurrenceRevision: 3,
            occurrenceKey: 'occurrence-1',
            status: [ReminderStatus.expired],
          ),
        );

    expect(captured!.method, 'reminder.list');
    expect(captured!.arguments['recurrence_revision'], 3);
    expect(captured!.arguments['occurrence_key'], 'occurrence-1');
    expect(captured!.arguments['status'], ['expired']);
    expect(result.result.data!.items, hasLength(1));
  });

  test(
    'adapter invokes reminder.reconcile_schedule with trigger source',
    () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return {
              'ok': true,
              'data': {
                'action': 'scheduled',
                'next_remind_at': '2026-08-05T00:00:00Z',
                'processed_due_count': 0,
                'failed_count': 0,
                'continuation_enqueued': false,
                'failed_reminder_ids': <String>[],
              },
              'error': null,
              'contract_version': 2,
              'request_id': 'reconcile-1',
            };
          });

      final result = await MethodChannelReminderAdapter(channel: channel)
          .reconcileSchedule(
            const ReconcileReminderScheduleRequestDto(
              triggerSource: ReminderScheduleTrigger.appResume,
              force: true,
            ),
          );

      expect(captured!.method, 'reminder.reconcile_schedule');
      expect(captured!.arguments, {
        'trigger_source': 'app_resume',
        'force': true,
      });
      expect(result.result.data!.nextRemindAt, DateTime.utc(2026, 8, 5));
    },
  );
}
