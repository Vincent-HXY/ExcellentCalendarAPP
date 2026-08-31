import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_habit_adapter.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/native_method_channel_contract.dart';
import 'package:excellent_calendar/native_contract/habit/habit_contract_enums.dart';
import 'package:excellent_calendar/native_contract/habit/habit_request_dtos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_habit_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/habit');
  const id = '00000001-1111-4111-8111-111111111111';

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'all ten methods use exact names, payloads and NativeResult data',
    () async {
      final fake = FakeHabitGateway(delay: Duration.zero);
      final detail = await fake.detail(
        const GetHabitDetailRequestDto(id: id, timezone: 'Asia/Shanghai'),
      );
      final list = await fake.list(
        const ListHabitsRequestDto(timezone: 'Asia/Shanghai'),
      );
      final mutation = await fake.create(_createRequest());
      final checkIn = await fake.checkIn(
        const HabitCheckInRequestDto(
          habitId: id,
          checkDate: '2026-08-28',
          status: HabitCheckInStatusContract.done,
          completedCountHundredths: null,
          note: null,
          timezone: 'Asia/Shanghai',
        ),
      );
      final daily = await fake.listDailyStatuses(
        const ListHabitDailyStatusesRequestDto(
          habitId: id,
          startDate: '2026-08-25',
          endDate: '2026-08-25',
          timezone: 'Asia/Shanghai',
        ),
      );
      final deleted = await fake.delete(
        HabitOptimisticRequestDto(
          id: id,
          expectedUpdatedAt: detail.habit.updatedAt,
          timezone: 'Asia/Shanghai',
        ),
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            final data = switch (call.method) {
              NativeHabitMethods.list => list.toJson(),
              NativeHabitMethods.detail => detail.toJson(),
              NativeHabitMethods.delete => deleted.toJson(),
              NativeHabitMethods.checkIn ||
              NativeHabitMethods.clearCheckIn => checkIn.toJson(),
              NativeHabitMethods.listDailyStatuses => daily.toJson(),
              _ => mutation.toJson(),
            };
            return {
              'ok': true,
              'data': data,
              'error': null,
              'contract_version': 2,
              'request_id': 'habit-test',
            };
          });
      final adapter = MethodChannelHabitAdapter(channel: channel);

      await adapter.create(_createRequest());
      await adapter.update(_updateRequest(detail.habit.updatedAt));
      await adapter.list(const ListHabitsRequestDto(timezone: 'Asia/Shanghai'));
      await adapter.detail(
        const GetHabitDetailRequestDto(id: id, timezone: 'Asia/Shanghai'),
      );
      final optimistic = HabitOptimisticRequestDto(
        id: id,
        expectedUpdatedAt: detail.habit.updatedAt,
        timezone: 'Asia/Shanghai',
      );
      await adapter.end(optimistic);
      await adapter.delete(optimistic);
      await adapter.checkIn(
        const HabitCheckInRequestDto(
          habitId: id,
          checkDate: '2026-08-28',
          status: HabitCheckInStatusContract.done,
          completedCountHundredths: null,
          note: null,
          timezone: 'Asia/Shanghai',
        ),
      );
      await adapter.clearCheckIn(
        const ClearHabitCheckInRequestDto(
          habitId: id,
          checkDate: '2026-08-28',
          timezone: 'Asia/Shanghai',
        ),
      );
      await adapter.listDailyStatuses(
        const ListHabitDailyStatusesRequestDto(
          habitId: id,
          startDate: '2026-08-25',
          endDate: '2026-08-25',
          timezone: 'Asia/Shanghai',
        ),
      );
      await adapter.setReminder(
        SetHabitReminderRequestDto(
          habitId: id,
          expectedUpdatedAt: detail.habit.updatedAt,
          reminder: const HabitReminderPlanInputDto.enabled('09:00'),
          timezone: 'Asia/Shanghai',
        ),
      );

      expect(calls.map((call) => call.method), [
        NativeHabitMethods.create,
        NativeHabitMethods.update,
        NativeHabitMethods.list,
        NativeHabitMethods.detail,
        NativeHabitMethods.end,
        NativeHabitMethods.delete,
        NativeHabitMethods.checkIn,
        NativeHabitMethods.clearCheckIn,
        NativeHabitMethods.listDailyStatuses,
        NativeHabitMethods.setReminder,
      ]);
      final checkInPayload = calls[6].arguments! as Map<Object?, Object?>;
      expect(checkInPayload, isNot(contains('source')));
      expect(
        checkInPayload.keys,
        containsAll(<String>[
          'habit_id',
          'check_date',
          'status',
          'completed_count_hundredths',
          'note',
          'timezone',
        ]),
      );
    },
  );
}

CreateHabitRequestDto _createRequest() => const CreateHabitRequestDto(
  title: '阅读',
  description: null,
  categoryId: null,
  targetCountHundredths: null,
  unit: null,
  startDate: '2026-08-28',
  endDate: '2026-09-17',
  reminder: HabitReminderPlanInputDto.disabled(),
  timezone: 'Asia/Shanghai',
);

UpdateHabitRequestDto _updateRequest(DateTime updatedAt) =>
    UpdateHabitRequestDto(
      id: '00000001-1111-4111-8111-111111111111',
      expectedUpdatedAt: updatedAt,
      title: '阅读',
      description: null,
      categoryId: null,
      targetCountHundredths: null,
      unit: null,
      startDate: '2026-08-28',
      endDate: '2026-09-17',
      timezone: 'Asia/Shanghai',
    );
