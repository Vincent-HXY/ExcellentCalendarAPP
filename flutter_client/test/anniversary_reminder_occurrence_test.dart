import 'dart:collection';

import 'package:excellent_calendar/application/anniversary/app_clock.dart';
import 'package:excellent_calendar/app/bootstrap/notification_permission_controller.dart';
import 'package:excellent_calendar/application/anniversary/anniversary_form_controller.dart';
import 'package:excellent_calendar/application/anniversary/anniversary_models.dart';
import 'package:excellent_calendar/application/anniversary/anniversary_occurrence_models.dart';
import 'package:excellent_calendar/application/anniversary/list_anniversary_occurrences_use_case.dart';
import 'package:excellent_calendar/data/anniversary/fake_anniversary_gateway.dart';
import 'package:excellent_calendar/gateway_interfaces/anniversary_occurrence_gateway.dart';
import 'package:excellent_calendar/native_contract/anniversary/anniversary_request_dtos.dart';
import 'package:excellent_calendar/native_contract/anniversary/anniversary_response_dtos.dart';
import 'package:excellent_calendar/native_contract/common/operation_response_dto.dart';
import 'package:excellent_calendar/native_contract/notification/notification_tap_payload_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_notification_gateway.dart';
import 'fixtures/notification_fixtures.dart';

void main() {
  group('Anniversary Reminder Contract', () {
    test(
      'serializes 0 and 365 day boundaries and rejects duplicates or six',
      () {
        final plan = AnniversaryReminderPlanInputDto(
          remindersEnabled: true,
          templates: const [
            AnniversaryReminderTemplateInputDto(
              advanceDays: 0,
              localTime: '00:00',
              isEnabled: true,
            ),
            AnniversaryReminderTemplateInputDto(
              advanceDays: 365,
              localTime: '23:59',
              isEnabled: false,
            ),
          ],
        );
        expect(plan.toJson()['templates'], hasLength(2));

        expect(
          () => AnniversaryReminderPlanInputDto(
            remindersEnabled: true,
            templates: List.generate(
              6,
              (index) => AnniversaryReminderTemplateInputDto(
                advanceDays: index,
                localTime: '09:00',
                isEnabled: true,
              ),
            ),
          ).toJson(),
          throwsFormatException,
        );
        expect(
          () => AnniversaryReminderPlanInputDto(
            remindersEnabled: true,
            templates: const [
              AnniversaryReminderTemplateInputDto(
                advanceDays: 7,
                localTime: '09:00',
                isEnabled: true,
              ),
              AnniversaryReminderTemplateInputDto(
                advanceDays: 7,
                localTime: '09:00',
                isEnabled: false,
              ),
            ],
          ).toJson(),
          throwsFormatException,
        );
        expect(
          () => const AnniversaryReminderTemplateInputDto(
            advanceDays: 1,
            localTime: '9:00',
            isEnabled: true,
          ).toJson(),
          throwsFormatException,
        );
      },
    );

    test('partial success stays data-saved with a stable warning', () {
      final response = AnniversaryMutationResponseDto.fromJson(
        _mutationFixture(
          scheduleStatus: 'pending_permission',
          notificationPermission: 'permanently_denied',
          reconciliationRequired: true,
          degradationReasons: const ['notification_permission_unavailable'],
        ),
      );

      expect(response.detail.reminderSettings.remindersEnabled, isTrue);
      expect(response.capability.scheduleReconciliationRequired, isTrue);
      expect(
        () => AnniversaryMutationResponseDto.fromJson(
          _mutationFixture(scheduleStatus: 'future_status'),
        ),
        throwsFormatException,
      );
    });
  });

  group('Anniversary occurrence pagination', () {
    test('loads every page without recomputing occurrences', () async {
      final gateway = _PagedOccurrenceGateway([
        AnniversaryOccurrencePage(
          items: [_occurrence(day: 1, anniversarySuffix: '1')],
          hasMore: true,
          nextCursor: 'annocc1.abcdefghijklmnopqrst',
        ),
        AnniversaryOccurrencePage(
          items: [_occurrence(day: 2, anniversarySuffix: '2')],
          hasMore: false,
          nextCursor: null,
        ),
      ]);
      final result = await ListAnniversaryOccurrencesUseCase(gateway)(
        AnniversaryOccurrenceQuery(
          rangeStartDate: DateTime(2026, 1, 1),
          rangeEndDate: DateTime(2027, 1, 1),
          timezone: 'Asia/Shanghai',
        ),
      );

      expect(result.map((item) => item.occurrenceDate.day), [1, 2]);
      expect(gateway.cursors, [null, 'annocc1.abcdefghijklmnopqrst']);
    });

    test('rejects duplicate items, cursor loops, and unstable order', () async {
      final duplicate = _occurrence(day: 1, anniversarySuffix: '1');
      await expectLater(
        ListAnniversaryOccurrencesUseCase(
          _PagedOccurrenceGateway([
            AnniversaryOccurrencePage(
              items: [duplicate],
              hasMore: true,
              nextCursor: 'annocc1.abcdefghijklmnopqrst',
            ),
            AnniversaryOccurrencePage(
              items: [duplicate],
              hasMore: false,
              nextCursor: null,
            ),
          ]),
        )(_query()),
        throwsA(isA<AnniversaryGatewayException>()),
      );

      await expectLater(
        ListAnniversaryOccurrencesUseCase(
          _PagedOccurrenceGateway([
            AnniversaryOccurrencePage(
              items: [_occurrence(day: 1, anniversarySuffix: '1')],
              hasMore: true,
              nextCursor: 'annocc1.abcdefghijklmnopqrst',
            ),
            AnniversaryOccurrencePage(
              items: [_occurrence(day: 2, anniversarySuffix: '2')],
              hasMore: true,
              nextCursor: 'annocc1.abcdefghijklmnopqrst',
            ),
          ]),
        )(_query()),
        throwsA(isA<AnniversaryGatewayException>()),
      );

      await expectLater(
        ListAnniversaryOccurrencesUseCase(
          _PagedOccurrenceGateway([
            AnniversaryOccurrencePage(
              items: [
                _occurrence(day: 2, anniversarySuffix: '2'),
                _occurrence(day: 1, anniversarySuffix: '1'),
              ],
              hasMore: false,
              nextCursor: null,
            ),
          ]),
        )(_query()),
        throwsA(isA<AnniversaryGatewayException>()),
      );
    });

    test('rejects empty, reversed, and over-400-day windows', () async {
      final useCase = ListAnniversaryOccurrencesUseCase(
        _PagedOccurrenceGateway(const []),
      );
      for (final end in [
        DateTime(2026, 1, 1),
        DateTime(2025, 12, 31),
        DateTime(2027, 2, 6),
      ]) {
        await expectLater(
          useCase(
            AnniversaryOccurrenceQuery(
              rangeStartDate: DateTime(2026, 1, 1),
              rangeEndDate: end,
              timezone: 'Asia/Shanghai',
            ),
          ),
          throwsA(isA<AnniversaryGatewayException>()),
        );
      }
    });
  });

  test(
    'form keeps reminder drafts and exposes partial-success warning',
    () async {
      final gateway = _PendingAnniversaryGateway(
        clock: FixedAppClock(DateTime(2026, 8, 24)),
      );
      final controller = AnniversaryFormController(gateway: gateway);
      addTearDown(controller.dispose);
      controller
        ..setTitle('项目纪念日')
        ..setDate(DateTime(2026, 9, 1));
      await controller.setRemindersEnabled(true);
      expect(
        controller.addReminder(const ReminderDraft(advanceDays: 7)),
        isTrue,
      );
      expect(
        controller.addReminder(const ReminderDraft(advanceDays: 7)),
        isFalse,
      );

      final saved = await controller.submit();

      expect(saved, isNotNull);
      expect(controller.reminders, hasLength(1));
      expect(controller.submitWarning, contains('通知权限未开启'));
    },
  );

  test(
    'permission denial keeps the enabled switch and reminder draft',
    () async {
      final calls = <String>[];
      final notificationGateway = FakeNotificationGateway(
        callLog: calls,
        initializeInvocation: successInvocation(initializedResponse),
        permissionStatusInvocation: successInvocation(
          permissionStatus(canPost: false, canScheduleExact: false),
        ),
        permissionRequestInvocation: successInvocation(
          permissionRequestResponse(canPost: false, canScheduleExact: false),
        ),
        openSettingsInvocation: successInvocation(
          const OperationResponseDto(performed: true),
        ),
        initialPayloadInvocation: successInvocation(
          const NotificationTapPayloadResponseDto(
            hasPayload: false,
            payload: null,
          ),
        ),
      );
      addTearDown(() {
        notificationGateway.openedController.close();
      });
      final controller = AnniversaryFormController(
        gateway: FakeAnniversaryGateway(
          clock: FixedAppClock(DateTime(2026, 8, 24)),
          seedDefaults: false,
        ),
        permissionController: NotificationPermissionController(
          notificationGateway,
        ),
      );
      addTearDown(controller.dispose);

      await controller.setRemindersEnabled(true);
      controller.addReminder(const ReminderDraft(advanceDays: 1));

      expect(controller.remindersEnabled, isTrue);
      expect(controller.reminders, hasLength(1));
      expect(controller.reminderCapabilityMessage, contains('通知权限未开启'));
      expect(calls, [
        'permission_status',
        'request_permission',
        'permission_status',
      ]);
    },
  );
}

AnniversaryOccurrenceQuery _query() => AnniversaryOccurrenceQuery(
  rangeStartDate: DateTime(2026, 1, 1),
  rangeEndDate: DateTime(2027, 1, 1),
  timezone: 'Asia/Shanghai',
);

AnniversaryOccurrenceSummary _occurrence({
  required int day,
  required String anniversarySuffix,
}) => AnniversaryOccurrenceSummary(
  anniversaryId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa$anniversarySuffix',
  occurrenceKey: 'bbbbbbbb-bbbb-5bbb-8bbb-bbbbbbbbbbb$anniversarySuffix',
  occurrenceDate: DateTime(2026, 1, day),
  sourceDate: DateTime(2020, 1, day),
  title: '纪念日 $day',
  calendarType: AnniversaryCalendarType.solar,
  isRepeating: true,
  yearsElapsed: 6,
  categoryId: null,
  importance: AnniversaryImportance.importantNotUrgent,
  hasActiveReminders: true,
  reminderCount: 1,
);

class _PagedOccurrenceGateway implements AnniversaryOccurrenceGateway {
  _PagedOccurrenceGateway(Iterable<AnniversaryOccurrencePage> pages)
    : _pages = Queue.of(pages);

  final Queue<AnniversaryOccurrencePage> _pages;
  final List<String?> cursors = [];

  @override
  Future<AnniversaryOccurrencePage> listOccurrencePage(
    AnniversaryOccurrencePageQuery query,
  ) async {
    cursors.add(query.cursor);
    return _pages.removeFirst();
  }
}

class _PendingAnniversaryGateway extends FakeAnniversaryGateway {
  _PendingAnniversaryGateway({required super.clock})
    : super(seedDefaults: false);

  @override
  Future<AnniversaryDetail> create(CreateAnniversaryPlan input) async {
    final detail = await super.create(input);
    return AnniversaryDetail(
      anniversary: detail.anniversary,
      kind: detail.kind,
      countdown: detail.countdown,
      iconKey: detail.iconKey,
      recurrence: detail.recurrence,
      reminders: detail.reminders,
      remindersEnabled: detail.remindersEnabled,
      activeReminderCount: detail.activeReminderCount,
      scheduleReconciliationRequired: true,
      scheduleCapability: const AnniversaryScheduleCapability(
        status: AnniversaryScheduleStatus.pendingPermission,
        scheduleReconciliationRequired: true,
        notificationPermissionStatus:
            AnniversaryNotificationPermissionStatus.permanentlyDenied,
        exactAlarmPermissionStatus:
            AnniversaryExactAlarmPermissionStatus.granted,
        degradationReasons: [
          AnniversaryScheduleDegradationReason
              .notificationPermissionUnavailable,
        ],
      ),
    );
  }
}

Map<String, dynamic> _mutationFixture({
  String scheduleStatus = 'scheduled_exact',
  String notificationPermission = 'granted',
  bool reconciliationRequired = false,
  List<String> degradationReasons = const [],
}) => {
  'data_saved': true,
  'detail': {
    'anniversary': {
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'title': '项目纪念日',
      'date': '2026-09-01',
      'calendar_type': 'solar',
      'category_id': null,
      'recurrence_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'note': null,
      'importance': 'important_noturgent',
      'created_at': '2026-08-23T00:00:00Z',
      'updated_at': '2026-08-23T00:00:00Z',
      'deleted_at': null,
    },
    'recurrence': {
      'recurrence_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'frequency': 'yearly',
      'interval': 1,
    },
    'countdown': {
      'relation': 'remaining',
      'days': 9,
      'target_occurrence_date': '2026-09-01',
      'iso_weekday': 2,
      'timezone': 'Asia/Shanghai',
      'calculated_at': '2026-08-23T00:00:00Z',
    },
    'reminder_settings': {
      'reminders_enabled': true,
      'templates': [
        {
          'template_key': 'cccccccc-cccc-5ccc-8ccc-cccccccccccc',
          'advance_days': 7,
          'local_time': '09:00',
          'timezone_mode': 'follow_device',
          'method': 'popup',
          'is_enabled': true,
        },
      ],
      'active_reminder_count': 1,
      'schedule_reconciliation_required': reconciliationRequired,
    },
  },
  'capability': {
    'schedule_status': scheduleStatus,
    'schedule_reconciliation_required': reconciliationRequired,
    'notification_permission_status': notificationPermission,
    'exact_alarm_permission_status': 'granted',
    'degradation_reasons': degradationReasons,
  },
};
