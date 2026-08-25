import 'package:excellent_calendar/application/ring/active_ring_session_controller.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/gateway_interfaces/ring_native_gateway.dart';
import 'package:excellent_calendar/native_contract/event/event_detail_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/get_event_detail_request_dto.dart';
import 'package:excellent_calendar/native_contract/ring/ring_contract_enums.dart';
import 'package:excellent_calendar/native_contract/ring/ring_state_dtos.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:excellent_calendar/presentation/ring/active_ring_session_page.dart';
import 'package:excellent_calendar/presentation/ring/ring_session_host.dart';
import 'package:excellent_calendar/presentation/ring/ring_settings_page.dart';
import 'package:excellent_calendar/presentation/inbox/components/inbox_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_ring_gateway.dart';
import 'fixtures/notification_fixtures.dart';
import 'fixtures/ring_fixtures.dart';

void main() {
  testWidgets(
    'settings page exposes ringtone, test, strong reminder and status',
    (tester) async {
      final calls = <String>[];
      final gateway = FakeRingGateway(
        callLog: calls,
        onGetState: () async => successInvocation(ringSnapshot()),
        onPickRingtone: (request) async => successInvocation(
          PickRingtoneResponseDto(
            selectionStatus: RingRingtoneSelectionStatus.cancelled,
            state: ringSnapshot(),
          ),
        ),
        onUpdateSettings: (request) async => successInvocation(
          ringSnapshot(
            sequence: 2,
            settingsRevision: 2,
            strongReminderEnabled: true,
          ),
        ),
        onTestRing: (request) async => successInvocation(
          ringSnapshot(sequence: 3, testState: RingTestState.audible),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: RingSettingsPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();

      expect(find.text('晨曦'), findsOneWidget);
      expect(find.text('强提醒'), findsOneWidget);
      expect(find.text('通知权限'), findsOneWidget);
      expect(find.text('测试响铃'), findsOneWidget);

      await tester.tap(find.text('铃声'));
      await tester.pumpAndSettle();
      expect(calls, contains('pick_ringtone'));
      expect(find.text('已取消选择铃声'), findsOneWidget);

      await tester.tap(find.text('测试响铃'));
      await tester.pumpAndSettle();
      expect(find.text('停止测试'), findsOneWidget);
    },
  );

  testWidgets('multi-item page has all stop/snooze but never all complete', (
    tester,
  ) async {
    final second = ringItem(
      itemDeliveryId: secondDeliveryId,
      itemAttemptId: secondDeliveryAttemptId,
      itemReminderId: secondReminderId,
      itemEventId: secondEventId,
    );
    final gateway = FakeRingGateway(
      onGetState: () async => successInvocation(
        ringSnapshot(
          sequence: 1,
          sessionRevision: 1,
          activeItems: [ringItem(), second],
        ),
      ),
    );
    final controller = ActiveRingSessionController(
      ringGateway: gateway,
      eventGateway: _EventDetailGateway(),
    );

    await tester.pumpWidget(
      MaterialApp(home: ActiveRingSessionPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 个日程正在响铃'), findsOneWidget);
    expect(find.text('关闭全部'), findsOneWidget);
    expect(find.text('全部稍后 10 分钟'), findsOneWidget);
    expect(find.text('全部完成'), findsNothing);
    expect(find.text('完成'), findsNWidgets(2));
    expect(find.text('晨会'), findsOneWidget);
    expect(find.text('代码评审'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('关闭全部'), findsOneWidget);
    expect(find.bySemanticsLabel('全部稍后 10 分钟'), findsOneWidget);
    semantics.dispose();

    controller.dispose();
    await gateway.eventController.close();
  });

  testWidgets('cold-start host opens each active session only once', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final initial = ringSnapshot(
      sequence: 1,
      sessionRevision: 1,
      activeItems: [ringItem()],
    );
    final gateway = FakeRingGateway(
      onGetState: () async => successInvocation(initial),
    );
    final controller = ActiveRingSessionController(
      ringGateway: gateway,
      eventGateway: _EventDetailGateway(),
    );
    var activeBuildCount = 0;

    await tester.pumpWidget(
      RingSessionHost(
        controller: controller,
        navigatorKey: navigatorKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('home')),
          routes: {
            '/ring/active': (_) {
              activeBuildCount += 1;
              return const Scaffold(body: Text('active ring route'));
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('active ring route'), findsOneWidget);
    expect(activeBuildCount, 1);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    gateway.eventController.add(
      RingStateChanged(
        RingStateChangedEventDto(
          reason: RingStateChangeReason.sessionChanged,
          state: ringSnapshot(
            sequence: 2,
            sessionRevision: 1,
            activeItems: [ringItem()],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(activeBuildCount, 1);
    controller.dispose();
    await gateway.eventController.close();
  });

  testWidgets('home overflow menu exposes the ring settings entry', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InboxTopBar(onOpenRingSettings: () => opened = true),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('响铃设置'), findsOneWidget);
    await tester.tap(find.text('响铃设置'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });
}

class _EventDetailGateway implements EventNativeGateway {
  @override
  Future<NativeInvocation<EventDetailResponseDto>> getEventDetail(
    GetEventDetailRequestDto request,
  ) async {
    return successInvocation(
      EventDetailResponseDto(
        event: EventResponseDto(
          id: request.id,
          title: request.id == eventId ? '晨会' : '代码评审',
          startAt: DateTime.utc(2026, 8, 22, 8),
          endAt: DateTime.utc(2026, 8, 22, 9),
          startDate: null,
          endDate: null,
          isAllDay: false,
          hasRecurrence: false,
          status: 'active',
          recurrenceId: null,
          recurrenceRevision: null,
          timezone: 'Asia/Shanghai',
          source: 'manual',
          createdAt: DateTime.utc(2026, 8, 21),
          updatedAt: DateTime.utc(2026, 8, 21),
        ),
        recurrence: null,
        reminders: const [],
        category: null,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
