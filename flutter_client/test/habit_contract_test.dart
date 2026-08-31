import 'package:excellent_calendar/native_contract/appearance/appearance_contract.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/habit/habit_contract_enums.dart';
import 'package:excellent_calendar/native_contract/habit/habit_request_dtos.dart';
import 'package:excellent_calendar/native_contract/habit/habit_response_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_habit_gateway.dart';

void main() {
  const id = '00000001-1111-4111-8111-111111111111';

  test('manual check-in exposes only the frozen public fields', () {
    final json = const HabitCheckInRequestDto(
      habitId: id,
      checkDate: '2026-08-28',
      status: HabitCheckInStatusContract.partial,
      completedCountHundredths: 125,
      note: '完成 1.25',
      timezone: 'Asia/Shanghai',
    ).toJson();

    expect(json.keys, {
      'habit_id',
      'check_date',
      'status',
      'completed_count_hundredths',
      'note',
      'timezone',
    });
    expect(
      json,
      isNot(contains(anyOf('source', 'occurrence_key', 'action_id'))),
    );
    expect(json['completed_count_hundredths'], 125);
  });

  test('safe-integer neighbours remain distinct and decimal numbers fail', () {
    final first = const CreateHabitRequestDto(
      title: '精确数量',
      description: null,
      categoryId: null,
      targetCountHundredths: 9007199254740990,
      unit: '次',
      startDate: '2026-08-28',
      endDate: '2026-08-28',
      reminder: HabitReminderPlanInputDto.disabled(),
      timezone: 'Asia/Shanghai',
    ).toJson();
    final second = const CreateHabitRequestDto(
      title: '精确数量',
      description: null,
      categoryId: null,
      targetCountHundredths: 9007199254740991,
      unit: '次',
      startDate: '2026-08-28',
      endDate: '2026-08-28',
      reminder: HabitReminderPlanInputDto.disabled(),
      timezone: 'Asia/Shanghai',
    ).toJson();

    expect(
      first['target_count_hundredths'],
      isNot(second['target_count_hundredths']),
    );
    expect(
      () => HabitTodayProgressResponseDto.fromJson({
        'as_of_date': '2026-08-28',
        'active_count': 1.0,
        'done_count': 1,
        'eligible_count': 1,
        'skipped_count': 0,
        'partial_count': 0,
        'absent_count': 0,
      }),
      throwsFormatException,
    );
  });

  test('fixture-derived list and detail DTOs round-trip strictly', () async {
    final fake = FakeHabitGateway(delay: Duration.zero);
    final list = await fake.list(
      const ListHabitsRequestDto(timezone: 'Asia/Shanghai'),
    );
    final detail = await fake.detail(
      const GetHabitDetailRequestDto(id: id, timezone: 'Asia/Shanghai'),
    );

    expect(HabitListResponseDto.fromJson(list.toJson()).items.length, 7);
    expect(HabitDetailResponseDto.fromJson(detail.toJson()).habit.id, id);
    expect(
      () => HabitDetailResponseDto.fromJson({...detail.toJson(), 'future': 1}),
      throwsFormatException,
    );
    final malformed = detail.toJson()..remove('statistics');
    expect(
      () => HabitDetailResponseDto.fromJson(malformed),
      throwsFormatException,
    );
  });

  test(
    'NativeResult rejects unknown version and malformed target branch',
    () async {
      final detail = await FakeHabitGateway(delay: Duration.zero).detail(
        const GetHabitDetailRequestDto(id: id, timezone: 'Asia/Shanghai'),
      );
      expect(
        () => NativeResultDto.fromJson(
          {
            'ok': true,
            'data': detail.toJson(),
            'error': null,
            'contract_version': 3,
          },
          (raw) =>
              HabitDetailResponseDto.fromJson(raw! as Map<String, dynamic>),
        ),
        throwsFormatException,
      );
      final malformed = detail.toJson();
      (malformed['habit']! as Map<String, dynamic>)['target_count_hundredths'] =
          1.25;
      expect(
        () => HabitDetailResponseDto.fromJson(malformed),
        throwsFormatException,
      );
    },
  );

  test('NativeResult rejects every malformed check-in status branch', () async {
    final binaryDetail = await FakeHabitGateway(
      delay: Duration.zero,
    ).detail(const GetHabitDetailRequestDto(id: id, timezone: 'Asia/Shanghai'));
    final quantityDetail = await FakeHabitGateway(delay: Duration.zero).detail(
      const GetHabitDetailRequestDto(
        id: '00000002-1111-4111-8111-111111111111',
        timezone: 'Asia/Shanghai',
      ),
    );

    final skippedWithQuantity = binaryDetail.toJson();
    final skipped = _historyCheckIn(skippedWithQuantity, 2);
    skipped['completed_count_hundredths'] = 100;
    skipped['target_count_snapshot_hundredths'] = 100;
    skipped['unit_snapshot'] = '次';
    skipped['completed_at'] = '2026-08-28T08:00:00Z';
    _expectMalformedDetailResult(skippedWithQuantity);

    final partialWithBinaryShape = quantityDetail.toJson();
    final partial = _historyCheckIn(partialWithBinaryShape, 0);
    partial['completed_count_hundredths'] = null;
    partial['target_count_snapshot_hundredths'] = null;
    partial['unit_snapshot'] = null;
    _expectMalformedDetailResult(partialWithBinaryShape);

    final incompleteDoneQuantity = quantityDetail.toJson();
    final done = _historyCheckIn(incompleteDoneQuantity, 1);
    done['target_count_snapshot_hundredths'] = null;
    _expectMalformedDetailResult(incompleteDoneQuantity);
  });

  test(
    'NativeResult rejects deleted disabled reminder and invalid history bounds',
    () async {
      final detail = await FakeHabitGateway(delay: Duration.zero).detail(
        const GetHabitDetailRequestDto(id: id, timezone: 'Asia/Shanghai'),
      );

      final deletedDisabledTemplate = detail.toJson();
      final settings =
          deletedDisabledTemplate['reminder_settings']! as Map<String, dynamic>;
      settings['is_enabled'] = false;
      settings['active_reminder_count'] = 0;
      final template = settings['template']! as Map<String, dynamic>;
      template['is_enabled'] = false;
      template['deleted_at'] = '2026-08-28T08:00:00Z';
      _expectMalformedDetailResult(deletedDisabledTemplate);

      final missingStart = detail.toJson()..['history_start_date'] = null;
      _expectMalformedDetailResult(missingStart);

      final mismatchedEnd = detail.toJson()
        ..['history_end_date'] = '2026-08-26';
      _expectMalformedDetailResult(mismatchedEnd);
    },
  );

  test(
    'appearance tokens reject unknown wire values instead of defaulting',
    () {
      expect(
        LocalAppearanceResponseDto.fromJson(const {
          'habit_progress_color': 'purple',
        }).habitProgressColor,
        HabitProgressColorToken.purple,
      );
      expect(
        () => LocalAppearanceResponseDto.fromJson(const {
          'habit_progress_color': 'custom',
        }),
        throwsFormatException,
      );
    },
  );
}

Map<String, dynamic> _historyCheckIn(Map<String, dynamic> detail, int index) =>
    ((detail['history']! as List<dynamic>)[index]
            as Map<String, dynamic>)['check_in']!
        as Map<String, dynamic>;

void _expectMalformedDetailResult(Map<String, dynamic> detail) {
  expect(
    () => NativeResultDto.fromJson({
      'ok': true,
      'data': detail,
      'error': null,
      'contract_version': 2,
    }, (raw) => HabitDetailResponseDto.fromJson(raw! as Map<String, dynamic>)),
    throwsFormatException,
  );
}
