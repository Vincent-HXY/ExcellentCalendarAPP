import 'package:excellent_calendar/presentation/new_schedule/new_schedule_draft.dart';
import 'package:excellent_calendar/presentation/new_schedule/selection/recurrence_selection_sheet.dart';
import 'package:excellent_calendar/presentation/new_schedule/selection/reminder_selection_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recurrence selection commits only after confirm', (
    tester,
  ) async {
    RecurrencePreset? selected;

    await tester.pumpWidget(
      _SheetHost(
        onOpen: (context) async {
          selected = await showRecurrenceSelectionSheet(
            context: context,
            initialValue: RecurrencePreset.once,
            onCustomUnsupported: () {},
          );
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(selected, isNull);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(selected, RecurrencePreset.weekly);
  });

  testWidgets('reminder selection supports multiple committed options', (
    tester,
  ) async {
    ReminderSelectionResult? selected;

    await tester.pumpWidget(
      _SheetHost(
        onOpen: (context) async {
          selected = await showReminderSelectionSheet(
            context: context,
            initialPresets: const {},
            initialCustomAdvanceMinutes: null,
            onRemainingTenPercentUnsupported: () {},
          );
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 分钟前'));
    await tester.tap(find.text('30 分钟前'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(selected?.presets, {
      ReminderPreset.minutes15,
      ReminderPreset.minutes30,
    });
  });

  testWidgets('custom reminder sheet returns one custom advance value', (
    tester,
  ) async {
    ReminderSelectionResult? selected;

    await tester.pumpWidget(
      _SheetHost(
        onOpen: (context) async {
          selected = await showReminderSelectionSheet(
            context: context,
            initialPresets: const {},
            initialCustomAdvanceMinutes: null,
            onRemainingTenPercentUnsupported: () {},
          );
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();
    expect(find.text('自定义：15 分钟前'), findsOneWidget);

    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();

    expect(selected?.presets, contains(ReminderPreset.custom));
    expect(selected?.customAdvanceMinutes, 15);
  });
}

class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.onOpen});

  final Future<void> Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => onOpen(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
  }
}
