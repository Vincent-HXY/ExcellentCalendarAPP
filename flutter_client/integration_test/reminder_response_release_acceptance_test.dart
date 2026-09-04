import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_timezone_adapter.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/delete_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/get_event_detail_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_contract_enums.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_draft_request_dto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _titlePrefix = 'CodexReminderResponseAcceptance-';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'formal Flutter Kotlin JNI C++ SQLite ReminderResponse chain',
    (_) async {
      final timezoneInvocation = await MethodChannelTimezoneAdapter()
          .getDeviceTimezone();
      expect(timezoneInvocation.result.ok, isTrue);
      final timezone = timezoneInvocation.result.data!.timezone;

      final gateway = MethodChannelEventAdapter();
      final now = DateTime.now().toUtc();
      final startAt = DateTime.utc(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      ).add(const Duration(days: 2));
      String? createdId;

      try {
        final created = await gateway.createEvent(
          CreateEventRequestDto.timed(
            title: '$_titlePrefix${now.microsecondsSinceEpoch}',
            startAt: startAt,
            endAt: startAt.add(const Duration(hours: 1)),
            timezone: timezone,
            source: 'manual',
            reminders: const [
              ReminderDraftRequestDto(
                targetType: 'event',
                advanceMinutes: 15,
                methods: ['popup'],
                source: 'manual',
              ),
            ],
          ),
        );
        expect(
          created.result.ok,
          isTrue,
          reason: created.result.error?.message,
        );
        createdId = created.result.data!.id;

        final detail = await gateway.getEventDetail(
          GetEventDetailRequestDto(id: createdId),
        );
        expect(detail.result.ok, isTrue, reason: detail.result.error?.message);
        final reminder = detail.result.data!.reminders.single;
        expect(reminder.targetType, ReminderTargetType.event);
        expect(reminder.advanceDays, isNull);
        expect(reminder.templateKey, isNull);
        expect(reminder.occurrenceDate, isNull);
        expect(reminder.localTime, isNull);
        expect(reminder.timezoneMode, isNull);
        expect(reminder.fulfillmentDeliveryId, isNull);
      } finally {
        if (createdId != null) {
          final deleted = await gateway.deleteEvent(
            DeleteEventRequestDto(id: createdId),
          );
          expect(
            deleted.result.ok,
            isTrue,
            reason: deleted.result.error?.message,
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
