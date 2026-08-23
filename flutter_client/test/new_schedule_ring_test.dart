import 'package:excellent_calendar/application/event/create_event_use_case.dart';
import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/data/category/fake_category_repository.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:excellent_calendar/presentation/new_schedule/components/app_switch.dart';
import 'package:excellent_calendar/presentation/new_schedule/new_schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_ring_gateway.dart';
import 'fakes/fake_timezone_gateway.dart';
import 'fixtures/notification_fixtures.dart';
import 'fixtures/ring_fixtures.dart';

void main() {
  testWidgets('ring toggle checks fresh capability before becoming enabled', (
    tester,
  ) async {
    final calls = <String>[];
    final ringGateway = FakeRingGateway(
      callLog: calls,
      onGetState: () async => successInvocation(ringSnapshot()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NewSchedulePage(
          createUseCase: CreateEventUseCase(_EventGateway()),
          timezoneService: TimezoneApplicationService(FakeTimezoneGateway()),
          categoryRepository: FakeCategoryRepository(),
          ringGateway: ringGateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(AppSwitch).at(1));
    await tester.tap(find.byType(AppSwitch).at(1));
    await tester.pumpAndSettle();

    expect(calls, ['get_state']);
    expect(
      tester.widget<AppSwitch>(find.byType(AppSwitch).at(1)).value,
      isTrue,
    );
    await ringGateway.eventController.close();
  });

  testWidgets('all-day schedule cannot enable ring or call capability', (
    tester,
  ) async {
    final calls = <String>[];
    final ringGateway = FakeRingGateway(
      callLog: calls,
      onGetState: () async => successInvocation(ringSnapshot()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NewSchedulePage(
          createUseCase: CreateEventUseCase(_EventGateway()),
          timezoneService: TimezoneApplicationService(FakeTimezoneGateway()),
          categoryRepository: FakeCategoryRepository(),
          ringGateway: ringGateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(AppSwitch).first);
    await tester.tap(find.byType(AppSwitch).first);
    await tester.pump();
    await tester.ensureVisible(find.byType(AppSwitch).at(1));
    await tester.tap(find.byType(AppSwitch).at(1));
    await tester.pumpAndSettle();

    expect(find.text('全天日程不支持响铃提醒'), findsOneWidget);
    expect(calls, isEmpty);
    expect(
      tester.widget<AppSwitch>(find.byType(AppSwitch).at(1)).value,
      isFalse,
    );
    await ringGateway.eventController.close();
  });
}

class _EventGateway implements EventNativeGateway {
  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) async {
    return successInvocation(
      EventResponseDto(
        id: eventId,
        title: request.title,
        startAt: request.startAt,
        endAt: request.endAt,
        startDate: request.startDate,
        endDate: request.endDate,
        isAllDay: request.isAllDay,
        hasRecurrence: false,
        status: 'active',
        recurrenceId: null,
        recurrenceRevision: null,
        timezone: request.timezone,
        source: request.source,
        createdAt: DateTime.utc(2026, 8, 22),
        updatedAt: DateTime.utc(2026, 8, 22),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
