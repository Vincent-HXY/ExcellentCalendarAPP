import 'package:excellent_calendar/presentation/inbox/components/add_task_button.dart';
import 'package:excellent_calendar/presentation/inbox/components/task_list_card.dart';
import 'package:excellent_calendar/presentation/inbox/models/inbox_task_view_data.dart';
import 'package:excellent_calendar/presentation/new_schedule/components/create_mode_segmented_control.dart';
import 'package:excellent_calendar/presentation/new_schedule/new_schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('segmented control switches between modes', (tester) async {
    var selectedMode = CreateScheduleMode.manual;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: CreateModeSegmentedControl(
                selectedMode: selectedMode,
                onChanged: (mode) {
                  setState(() {
                    selectedMode = mode;
                  });
                },
              ),
            );
          },
        ),
      ),
    );

    expect(selectedMode, CreateScheduleMode.manual);
    await tester.tap(find.text('一键识别'));
    await tester.pump(const Duration(milliseconds: 140));
    expect(selectedMode, CreateScheduleMode.aiRecognition);
    await tester.pumpAndSettle();

    await tester.tap(find.text('手动填写'));
    await tester.pump(const Duration(milliseconds: 140));
    expect(selectedMode, CreateScheduleMode.manual);
  });

  testWidgets('task group card expands and collapses from the header', (
    tester,
  ) async {
    var isExpanded = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: TaskGroupCard(
                title: 'Group',
                tasks: const [
                  InboxTaskViewData(
                    id: '1',
                    title: 'Visible task',
                    importance: TaskImportance.unimportantNotUrgent,
                    isCompleted: false,
                  ),
                ],
                isExpanded: isExpanded,
                onHeaderTap: () {
                  setState(() {
                    isExpanded = !isExpanded;
                  });
                },
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Visible task'), findsOneWidget);
    await tester.tap(find.text('Group'));
    await tester.pumpAndSettle();
    expect(find.text('Visible task'), findsNothing);

    await tester.tap(find.text('Group'));
    await tester.pumpAndSettle();
    expect(find.text('Visible task'), findsOneWidget);
  });

  testWidgets('add button waits for tap up before running callback', (
    tester,
  ) async {
    var openCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AddTaskButton(
              onPressed: () async {
                openCount += 1;
              },
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AddTaskButton)),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(openCount, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(openCount, 1);
  });

  testWidgets('add button tap cancel restores without running callback', (
    tester,
  ) async {
    var openCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AddTaskButton(
              onPressed: () async {
                openCount += 1;
              },
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AddTaskButton)),
    );
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(openCount, 0);
  });
}
