import 'package:excellent_calendar/presentation/home/main_tab_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('four bottom tabs switch between ready and placeholder pages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainTabPage(
          scheduleBuilder: (_) => const ColoredBox(
            color: Colors.white,
            child: Center(child: Text('日程首页内容')),
          ),
          profileBuilder: (_) => const ColoredBox(
            color: Colors.white,
            child: Center(child: Text('个人信息内容')),
          ),
        ),
      ),
    );

    expect(find.text('日程'), findsOneWidget);
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('日程首页内容'), findsOneWidget);

    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    expect(find.text('日历板块正在开发中'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('搜索板块正在开发中'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('个人信息内容'), findsOneWidget);

    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    expect(find.text('日程首页内容'), findsOneWidget);
  });

  testWidgets('profile tab is built lazily', (tester) async {
    var profileBuildCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MainTabPage(
          scheduleBuilder: (_) => const SizedBox(),
          profileBuilder: (_) {
            profileBuildCount += 1;
            return const Text('个人信息内容');
          },
        ),
      ),
    );

    expect(profileBuildCount, 0);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(profileBuildCount, 1);

    await tester.tap(find.text('日程'));
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(profileBuildCount, 1);
  });
}
