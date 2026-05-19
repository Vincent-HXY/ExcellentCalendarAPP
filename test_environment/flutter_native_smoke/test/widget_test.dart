import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_native_smoke/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('excellent_calendar/native_smoke');

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

  testWidgets('shows native ping result', (tester) async {
    await tester.pumpWidget(const SmokeTestApp());
    await tester.pump();

    expect(find.text('pong from mocked native channel'), findsOneWidget);
  });
}
