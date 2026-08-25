import 'package:excellent_calendar/application/anniversary/anniversary_models.dart';
import 'package:excellent_calendar/application/anniversary/anniversary_occurrence_models.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_anniversary_adapter.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_timezone_adapter.dart';
import 'package:excellent_calendar/data/anniversary/native_anniversary_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _titlePrefix = 'CodexAnniversaryAcceptance-';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'formal Flutter Kotlin JNI C++ Storage v3 Anniversary chain',
    (_) async {
      final timezoneAdapter = MethodChannelTimezoneAdapter();
      final timezoneInvocation = await timezoneAdapter.getDeviceTimezone();
      expect(timezoneInvocation.result.ok, isTrue);
      final timezone = timezoneInvocation.result.data!.timezone;
      expect(timezone, isNotEmpty);

      final gateway = NativeAnniversaryGateway(
        nativeGateway: MethodChannelAnniversaryAdapter(),
        timezoneGateway: timezoneAdapter,
      );
      final now = DateTime.now();
      final sourceDate = DateTime(now.year - 3, now.month, now.day);
      final suffix = now.microsecondsSinceEpoch.toString();
      final originalTitle = '$_titlePrefix$suffix';
      final updatedTitle = '$originalTitle-updated';
      String? createdId;

      try {
        final created = await gateway.create(
          CreateAnniversaryPlan(
            anniversary: AnniversaryDraft(
              title: originalTitle,
              date: sourceDate,
              calendarType: AnniversaryCalendarType.solar,
              categoryId: null,
              note: 'Flutter physical-device acceptance',
              importance: AnniversaryImportance.importantNotUrgent,
            ),
            kind: AnniversaryKind.anniversary,
            recurrence: const RecurrenceDraft.yearly(),
            reminders: const [
              ReminderDraft(
                advanceDays: 0,
                localTime: AnniversaryReminderLocalTime(23, 59),
              ),
            ],
          ),
        );
        createdId = created.anniversary.id;
        expect(created.anniversary.title, originalTitle);
        expect(created.recurrence, isNotNull);
        expect(created.remindersEnabled, isFalse);
        expect(created.reminders, hasLength(1));

        final detail = await gateway.getById(createdId);
        expect(detail.anniversary.title, originalTitle);
        expect(detail.anniversary.note, 'Flutter physical-device acceptance');
        expect(detail.reminders.single.localTime.wireValue, '23:59');

        final enabled = await gateway.setRemindersEnabled(
          createdId,
          remindersEnabled: true,
        );
        expect(enabled.remindersEnabled, isTrue);
        expect(
          enabled.scheduleCapability.status,
          isIn(const [
            AnniversaryScheduleStatus.scheduledExact,
            AnniversaryScheduleStatus.scheduledApproximate,
            AnniversaryScheduleStatus.pendingPermission,
            AnniversaryScheduleStatus.pendingReconciliation,
          ]),
        );

        final disabled = await gateway.setRemindersEnabled(
          createdId,
          remindersEnabled: false,
        );
        expect(disabled.remindersEnabled, isFalse);
        expect(
          disabled.scheduleCapability.status,
          AnniversaryScheduleStatus.notRequired,
        );
        expect(
          disabled.anniversary.updatedAt,
          isNot(created.anniversary.updatedAt),
        );

        final occurrences = await gateway.listOccurrencePage(
          AnniversaryOccurrencePageQuery(
            query: AnniversaryOccurrenceQuery(
              rangeStartDate: DateTime(now.year, now.month, now.day),
              rangeEndDate: DateTime(now.year, now.month, now.day + 1),
              timezone: timezone,
            ),
            cursor: null,
          ),
        );
        expect(
          occurrences.items.any(
            (item) =>
                item.anniversaryId == createdId &&
                item.occurrenceDate == DateTime(now.year, now.month, now.day),
          ),
          isTrue,
        );

        await expectLater(
          gateway.update(
            _updatePlan(
              id: createdId,
              expectedUpdatedAt: created.anniversary.updatedAt,
              title: updatedTitle,
              sourceDate: sourceDate,
            ),
          ),
          throwsA(
            isA<AnniversaryGatewayException>().having(
              (error) => error.code,
              'ANNIVERSARY_UPDATE_CONFLICT',
              AnniversaryFailureCode.updateConflict,
            ),
          ),
        );

        final detailAfterConflict = await gateway.getById(createdId);
        expect(detailAfterConflict.anniversary.title, originalTitle);
        expect(
          detailAfterConflict.anniversary.note,
          'Flutter physical-device acceptance',
        );
        expect(
          detailAfterConflict.anniversary.importance,
          AnniversaryImportance.importantNotUrgent,
        );
        expect(detailAfterConflict.remindersEnabled, isFalse);
        expect(
          detailAfterConflict.anniversary.updatedAt,
          disabled.anniversary.updatedAt,
        );

        final listAfterConflict = await gateway.list(
          const AnniversaryListQuery(),
        );
        final listedAfterConflict = listAfterConflict.items.singleWhere(
          (item) => item.anniversary.id == createdId,
        );
        expect(listedAfterConflict.anniversary.title, originalTitle);
        expect(
          listedAfterConflict.anniversary.importance,
          AnniversaryImportance.importantNotUrgent,
        );
        expect(
          listedAfterConflict.anniversary.updatedAt,
          disabled.anniversary.updatedAt,
        );

        final updated = await gateway.update(
          _updatePlan(
            id: createdId,
            expectedUpdatedAt: disabled.anniversary.updatedAt,
            title: updatedTitle,
            sourceDate: sourceDate,
          ),
        );
        expect(updated.anniversary.title, updatedTitle);
        expect(
          updated.anniversary.importance,
          AnniversaryImportance.importantUrgent,
        );

        final listed = await gateway.list(const AnniversaryListQuery());
        expect(
          listed.items.any(
            (item) =>
                item.anniversary.id == createdId &&
                item.anniversary.title == updatedTitle,
          ),
          isTrue,
        );

        await gateway.delete(createdId);
        createdId = null;
      } finally {
        if (createdId != null) {
          await gateway.delete(createdId);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

UpdateAnniversaryPlan _updatePlan({
  required String id,
  required DateTime expectedUpdatedAt,
  required String title,
  required DateTime sourceDate,
}) => UpdateAnniversaryPlan(
  id: id,
  expectedUpdatedAt: expectedUpdatedAt,
  anniversary: AnniversaryDraft(
    title: title,
    date: sourceDate,
    calendarType: AnniversaryCalendarType.solar,
    categoryId: null,
    note: 'Updated through the complete native chain',
    importance: AnniversaryImportance.importantUrgent,
  ),
  kind: AnniversaryKind.anniversary,
  recurrence: const RecurrenceDraft.yearly(),
  reminders: const [
    ReminderDraft(
      advanceDays: 0,
      localTime: AnniversaryReminderLocalTime(23, 59),
    ),
  ],
);
