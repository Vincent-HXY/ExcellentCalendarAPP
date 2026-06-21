import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_reminder_adapter.dart';
import 'package:excellent_calendar/native_contract/reminder/cancel_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/create_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_contract_enums.dart';
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
}
