import 'package:excellent_calendar/presentation/event_detail/models/event_detail_ui_state.dart';
import 'package:excellent_calendar/presentation/event_detail/pages/event_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('event detail presents preview data and delegates actions', (
    tester,
  ) async {
    var moreCalls = 0;
    var editCalls = 0;
    var completeCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: EventDetailPage(
          state: EventDetailUiState.preview(),
          onMore: () => moreCalls += 1,
          onEdit: () => editCalls += 1,
          onComplete: () => completeCalls += 1,
        ),
      ),
    );

    expect(find.text('\u65e5\u7a0b\u8be6\u60c5'), findsOneWidget);
    expect(find.text('\u4ea7\u54c1\u9700\u6c42\u8bc4\u5ba1'), findsOneWidget);
    expect(find.text('\u65f6\u95f4\u5b89\u6392'), findsOneWidget);
    expect(find.text('\u8be6\u60c5\u4e0e\u5907\u6ce8'), findsOneWidget);
    expect(find.text('\u72b6\u6001\u4e0e\u53c2\u4e0e'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.tap(find.text('\u7f16\u8f91'));
    await tester.tap(find.text('\u5b8c\u6210'));
    await tester.pump();

    expect(moreCalls, 1);
    expect(editCalls, 1);
    expect(completeCalls, 1);
  });

  testWidgets('event detail has no layout exception at common phone widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in [
      const Size(360, 640),
      const Size(393, 852),
      const Size(411, 891),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailPage.preview(
            eventId: 'event-${size.width}x${size.height}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'size: $size');
    }
  });
}
