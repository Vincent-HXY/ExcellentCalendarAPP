import 'package:excellent_calendar/main.dart';
import 'package:excellent_calendar/gateway_interfaces/inbox_task_gateway.dart';
import 'package:excellent_calendar/presentation/inbox/inbox_page.dart';
import 'package:excellent_calendar/presentation/inbox/models/inbox_task_view_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Inbox page smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ExcellentCalendarApp());
    await tester.pump();

    expect(find.text('日程'), findsOneWidget);
    expect(find.text('Design homepage'), findsOneWidget);
    expect(find.text('Prepare Android smoke run'), findsOneWidget);

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
        home: InboxPage(gateway: _DenseInboxTaskGateway()),
      ),
    );
    await tester.pump();

    expect(find.text('Task 01'), findsOneWidget);
    expect(find.text('Task 12'), findsOneWidget);
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
