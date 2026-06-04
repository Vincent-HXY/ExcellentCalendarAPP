// 文件作用：验证当前 Flutter 客户端的首页、新建页入口和 EventDraft 提交流程。
// 设计边界：测试使用 fake gateway/use case，不依赖真实存储、Kotlin 或 C++。
import 'package:excellent_calendar/main.dart';
import 'package:excellent_calendar/gateway_interfaces/inbox_task_gateway.dart';
import 'package:excellent_calendar/gateway_interfaces/schedule_create_use_case.dart';
import 'package:excellent_calendar/presentation/inbox/inbox_page.dart';
import 'package:excellent_calendar/presentation/inbox/models/inbox_task_view_data.dart';
import 'package:excellent_calendar/presentation/new_schedule/new_schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Inbox page smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ExcellentCalendarApp());
    await tester.pump();

    expect(find.text('日程'), findsOneWidget);
    expect(find.text('未完成'), findsOneWidget);
    expect(find.text('即将到期'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('Buy notebook'), findsOneWidget);
    expect(find.text('Prepare Android smoke run'), findsOneWidget);
    expect(
      find.text('Write follow-up README for frontend test flow'),
      findsNothing,
    );

    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();

    expect(
      find.text('Write follow-up README for frontend test flow'),
      findsOneWidget,
    );

    expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
    expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });

  testWidgets('Schedule card keeps 12 rows visible on a 390x844 screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: InboxPage(
          gateway: _DenseInboxTaskGateway(),
          scheduleCreateUseCase: _NoopScheduleCreateUseCase(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Task 01'), findsOneWidget);
    expect(find.text('Task 12'), findsOneWidget);
  });

  testWidgets('FAB opens the new schedule page with a custom transition', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExcellentCalendarApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('新建日程'), findsOneWidget);
    expect(find.text('手动填写'), findsOneWidget);
    expect(find.text('一键识别'), findsOneWidget);
    expect(find.text('请输入日程名称'), findsOneWidget);
  });

  testWidgets('New schedule submit builds an EventDraft and calls use case', (
    WidgetTester tester,
  ) async {
    final useCase = _RecordingScheduleCreateUseCase();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: NewSchedulePage(createUseCase: useCase),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '团队会议');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final draft = useCase.lastDraft;
    // 关键数据：这些断言锁定了当前页面里的硬编码默认值，
    // 后续接入真实时间选择、分类和时区时应同步调整。
    expect(draft, isNotNull);
    expect(draft!.title, '团队会议');
    expect(draft.categoryId, '1');
    expect(draft.source, '手动添加');
    expect(draft.isAllDay, isFalse);
    expect(draft.hasRecurrence, isFalse);
    expect(draft.startAt, DateTime(2026, 6, 3, 8));
    expect(draft.endAt, DateTime(2026, 6, 3, 9));
    expect(draft.timezone, 'GMT+08:00 北京');
  });
}

class _DenseInboxTaskGateway implements InboxTaskGateway {
  @override
  Future<List<InboxTaskViewData>> loadInboxTasks() async {
    return List.generate(14, (index) {
      final taskNumber = index + 1;
      return InboxTaskViewData(
        id: 'dense-task-$taskNumber',
        title: 'Task ${taskNumber.toString().padLeft(2, '0')}',
        dueDateLabel: 'Jun ${taskNumber + 2}',
        importance: taskNumber.isEven
            ? TaskImportance.importantNotUrgent
            : TaskImportance.unimportantNotUrgent,
        isCompleted: taskNumber == 3,
      );
    });
  }
}

class _NoopScheduleCreateUseCase implements ScheduleCreateUseCase {
  @override
  Future<void> createSchedule(EventDraft draft) async {}
}

class _RecordingScheduleCreateUseCase implements ScheduleCreateUseCase {
  EventDraft? lastDraft;

  @override
  Future<void> createSchedule(EventDraft draft) async {
    lastDraft = draft;
  }
}
