import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_native_smoke/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('excellent_calendar/native_smoke');

  // 每个用例前安装一个假的平台端处理器；这里验证的是 Flutter 对通道结果的展示，
  // 不会真正进入 Kotlin/JNI/C++。真正的全链路测试需要在设备上使用 integration_test。
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pingNative') {
            return 'pong from mocked native channel';
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // 目的：验证页面收到 pingNative 响应后更新文本；方法：pump 页面并查找 mock 返回内容。
  testWidgets('shows native ping result', (tester) async {
    await tester.pumpWidget(const SmokeTestApp());
    await tester.pump();

    expect(find.text('pong from mocked native channel'), findsOneWidget);
  });
}
