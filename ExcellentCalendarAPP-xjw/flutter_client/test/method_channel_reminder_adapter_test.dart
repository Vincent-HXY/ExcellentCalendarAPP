import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_reminder_adapter.dart';
import 'package:excellent_calendar/native_contract/reminder/cancel_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/create_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_contract_enums.dart';
import 'package:excellent_calendar/native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/schedule_pending_reminders_dto.dart';
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
      const CancelReminderRequestDto(
        id: 'reminder-1',
        reason: 'User cancelled reminder.',
      ),
    );

    expect(captured!.method, 'reminder.cancel');
    expect(captured!.arguments, {
      'id': 'reminder-1',
      'reason': 'User cancelled reminder.',
    });
  });

  // 目的：确认非 NativeResult 的平台返回不会被误判为成功；方法：返回坏数据并检查标准内部错误。
  test(
    'adapter converts PlatformException into transport invocation',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'bridge_unavailable');
          });

      final invocation = await MethodChannelReminderAdapter(
        channel: channel,
      ).cancelReminder(const CancelReminderRequestDto(id: 'reminder-1'));

      expect(invocation.isNativeResult, isFalse);
      expect(invocation.result.error!.code, 'NATIVE_INTERNAL_ERROR');
      expect(invocation.result.error!.details!['method'], 'reminder.cancel');
    },
  );

  test('adapter invokes reminder.schedule_pending with UTC range', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return {
            'ok': true,
            'data': {
              'scheduled_count': 1,
              'skipped_count': 0,
              'failed_count': 0,
              'unsupported_method_count': 0,
              'has_more': false,
              'failed_reminder_ids': <String>[],
              'unsupported_reminder_ids': <String>[],
            },
            'error': null,
            'contract_version': 1,
            'request_id': 'schedule-1',
          };
        });

    await MethodChannelReminderAdapter(channel: channel).schedulePending(
      SchedulePendingRemindersRequestDto(
        fromAt: DateTime.utc(2026, 7, 5),
        toAt: DateTime.utc(2026, 7, 12),
        limit: 128,
      ),
    );

    expect(captured!.method, 'reminder.schedule_pending');
    expect(captured!.arguments['limit'], 128);
    expect(captured!.arguments['from_at'], '2026-07-05T00:00:00.000Z');
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
              'contract_version': 1,
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
