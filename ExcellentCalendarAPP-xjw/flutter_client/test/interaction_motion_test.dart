import 'package:excellent_calendar/presentation/inbox/components/add_task_button.dart';
import 'package:excellent_calendar/presentation/inbox/components/task_list_card.dart';
import 'package:excellent_calendar/presentation/inbox/components/task_list_item.dart';
import 'package:excellent_calendar/presentation/inbox/models/inbox_task_view_data.dart';
import 'package:excellent_calendar/presentation/new_schedule/components/create_mode_segmented_control.dart';
import 'package:excellent_calendar/presentation/new_schedule/new_schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 目的：验证分段控件能切换创建模式；方法：pump 组件、模拟点击并检查回调值和选中状态。
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

  // 目的：验证任务组标题可控制展开/折叠；方法：点击 header 后检查子任务是否存在。
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

  // 目的：验证完成动画必须等待原生成功，并分阶段移除；方法：手动完成 Future，逐帧检查回调。
  testWidgets(
    'task completion waits for native success then removes in phases',
    (tester) async {
      var completeCalls = 0;
      var removalCalls = 0;
      var isVisible = true;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: isVisible
                    ? TaskListItem(
                        task: const InboxTaskViewData(
                          id: 'event-1',
                          title: 'Complete this schedule',
                          importance: TaskImportance.unimportantNotUrgent,
                          isCompleted: false,
                        ),
                        showDivider: false,
                        onComplete: () async {
                          completeCalls += 1;
                          return true;
                        },
                        onRemovalFinished: () {
                          removalCalls += 1;
                          setState(() {
                            isVisible = false;
                          });
                        },
                      )
                    : const SizedBox.shrink(),
              );
            },
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('完成日程'));
      await tester.pump();
      expect(completeCalls, 1);
      expect(removalCalls, 0);

      await tester.pump(const Duration(milliseconds: 219));
      expect(removalCalls, 0);
      await tester.pumpAndSettle();
      expect(removalCalls, 1);
    },
  );

  // 目的：避免已完成项目被误当作可点击的“重新打开”按钮；方法：检查图标存在但无操作语义。
  testWidgets('completed task check has no reopen action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TaskListItem(
            task: InboxTaskViewData(
              id: 'event-1',
              title: 'Completed schedule',
              importance: TaskImportance.unimportantNotUrgent,
              isCompleted: true,
            ),
            showDivider: false,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('完成日程'), findsNothing);
  });

  // 目的：验证已完成数量加载中的占位和加载后的总数；方法：重建不同状态的组件并查找文本。
  testWidgets('collapsed completed group shows loading then loaded total', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TaskListCard(tasks: [], completedCountLabel: '…'),
        ),
      ),
    );

    expect(find.text('…'), findsOneWidget);
    expect(find.text('7'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TaskListCard(tasks: [], completedCountLabel: '7'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('…'), findsNothing);
    expect(find.text('7'), findsOneWidget);
  });

  // 目的：确保按下按钮时不提前执行，完整点击结束后才触发；方法：分别发送 down/up 手势并计数。
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

  // 目的：验证取消手势不会误触创建操作；方法：发送 tapCancel 并检查回调次数为零。
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
