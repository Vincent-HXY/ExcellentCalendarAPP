import 'package:excellent_calendar/presentation/new_schedule/date_time_picker/picker_date_math.dart';
import 'package:excellent_calendar/presentation/new_schedule/date_time_picker/picker_design_tokens.dart';
import 'package:excellent_calendar/presentation/new_schedule/date_time_picker/schedule_date_time_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 目的：验证选择器打开时正确显示外部初始值；方法：传入固定时间并查找日期、时间文本。
  testWidgets('picker shows the provided initial date time', (tester) async {
    await _pumpPickerHost(tester, initial: DateTime(2026, 6, 9, 14, 30));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('选择开始时间'), findsOneWidget);
    expect(find.text('2026年6月9日'), findsOneWidget);
    expect(find.text('14:30'), findsOneWidget);
    expect(find.text('2026年6月'), findsOneWidget);
  });

  // 目的：验证时间滚轮从午夜附近循环显示；方法：打开时间步骤并检查小时、分钟选项。
  testWidgets('time initial step opens wheel and loops around 00:00', (
    tester,
  ) async {
    await _pumpPickerHost(
      tester,
      initial: DateTime(2026, 6, 9),
      initialStep: PickerInitialStep.time,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(ListWheelScrollView), findsNWidgets(2));
    expect(find.text('00'), findsWidgets);
    expect(find.text('23'), findsWidgets);
    expect(find.text('59'), findsWidgets);
  });

  // 目的：锁定滚轮的交互参数；方法：读取 ListWheelScrollView 属性并比较放大率、尺寸和物理效果。
  testWidgets('time wheels use the native continuous magnifier', (
    tester,
  ) async {
    await _pumpPickerHost(
      tester,
      initial: DateTime(2026, 6, 9, 14, 30),
      initialStep: PickerInitialStep.time,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final wheels = tester.widgetList<ListWheelScrollView>(
      find.byType(ListWheelScrollView),
    );

    expect(wheels, hasLength(2));
    for (final wheel in wheels) {
      expect(wheel.useMagnifier, isTrue);
      expect(wheel.magnification, PickerSizes.wheelMagnification);
      expect(
        wheel.overAndUnderCenterOpacity,
        PickerSizes.wheelOverAndUnderOpacity,
      );
      expect(wheel.itemExtent, PickerSizes.wheelItemExtent);
      expect(wheel.physics, isA<FixedExtentScrollPhysics>());
    }
  });

  // 目的：验证跨年时上月/下月导航正确；方法：从一月前后导航并检查月份标题。
  testWidgets(
    'month navigation supports previous and next including year edge',
    (tester) async {
      await _pumpPickerHost(tester, initial: DateTime(2026, 1, 9, 14, 30));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('2026年1月'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('2025年12月'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('2026年1月'), findsOneWidget);
    },
  );

  // 目的：验证选择日期后进入时间步骤，返回日期步骤仍保留选择；方法：模拟点击并检查页面组件。
  testWidgets('selecting a calendar day moves to the time wheel', (
    tester,
  ) async {
    await _pumpPickerHost(tester, initial: DateTime(2026, 6, 9, 14, 30));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('10').first);
    await tester.pumpAndSettle();

    expect(find.text('2026年6月10日'), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));

    await tester.tap(find.text('2026年6月10日'));
    await tester.pumpAndSettle();
    expect(find.text('2026年6月'), findsOneWidget);

    await tester.tap(find.text('14:30'));
    await tester.pumpAndSettle();
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));
  });

  // 目的：验证月份标题可以进入年月日滚轮并提交；方法：切换视图、滚动选择并检查返回月份。
  testWidgets('month title opens year month day wheel and commits back', (
    tester,
  ) async {
    await _pumpPickerHost(tester, initial: DateTime(2026, 6, 9, 14, 30));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2026年6月'));
    await tester.pumpAndSettle();
    expect(find.byType(ListWheelScrollView), findsNWidgets(3));

    await tester.tap(find.text('2026年6月').first);
    await tester.pumpAndSettle();
    expect(find.text('2026年6月'), findsOneWidget);
  });

  // 目的：防止窄屏布局溢出；方法：设置较小测试视口、打开三列滚轮并检查布局异常。
  testWidgets('year month day wheel does not overflow on narrow widths', (
    tester,
  ) async {
    for (final width in <double>[360, 390, 412]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpPickerHost(
        tester,
        initial: DateTime(2026, 12, 31, 14, 30),
        initialStep: PickerInitialStep.yearMonthDay,
        textScaler: TextScaler.linear(1.3),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(ListWheelScrollView), findsNWidgets(3));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }
  });

  // 目的：区分取消与确认的提交语义；方法：两次打开选择器，分别取消/确认并检查外部值。
  testWidgets('cancel keeps outer value and confirm updates it', (
    tester,
  ) async {
    final initial = DateTime(2026, 6, 9, 14, 30);
    DateTime selected = initial;

    await _pumpPickerHost(
      tester,
      initial: initial,
      onSelected: (value) => selected = value,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('10').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(selected, initial);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2026, 6, 10, 14, 30));
  });

  // 目的：验证同一选择器组件可用于结束时间；方法：传入结束时间标题和初始值并检查显示。
  testWidgets('picker can be reused for end time', (tester) async {
    await _pumpPickerHost(
      tester,
      initial: DateTime(2026, 6, 9, 14, 30),
      target: PickerTarget.end,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('选择结束时间'), findsOneWidget);
  });

  // 目的：验证闰年和月末修正规则；方法：直接调用纯日期函数检查典型边界值。
  test('picker date math handles leap years and month-end clamping', () {
    expect(
      PickerDateMath.clampedDate(year: 2024, month: 2, day: 29),
      DateTime(2024, 2, 29),
    );
    expect(
      PickerDateMath.clampedDate(year: 2025, month: 2, day: 29),
      DateTime(2025, 2, 28),
    );
    expect(
      PickerDateMath.clampedDate(year: 2026, month: 4, day: 31),
      DateTime(2026, 4, 30),
    );
    expect(PickerDateMath.shiftMonth(DateTime(2026), -1), DateTime(2025, 12));
  });
}

// 构建带按钮的最小 Material 宿主；点击按钮后打开被测日期时间选择器。
Future<void> _pumpPickerHost(
  WidgetTester tester, {
  required DateTime initial,
  PickerTarget target = PickerTarget.start,
  PickerInitialStep initialStep = PickerInitialStep.calendar,
  TextScaler textScaler = TextScaler.noScaling,
  ValueChanged<DateTime>? onSelected,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final result = await showScheduleDateTimePicker(
                      context: context,
                      initialDateTime: initial,
                      timezone: 'GMT+08:00 北京',
                      target: target,
                      initialStep: initialStep,
                    );
                    if (result != null) {
                      onSelected?.call(result.localDateTime);
                    }
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
