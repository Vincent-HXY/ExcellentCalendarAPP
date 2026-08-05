import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_timezone_adapter.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/native_contract/runtime/localize_instants_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/resolve_local_datetime_dto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('excellent_calendar/timezone_test');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'runtime.device_timezone' => _success({
              'timezone': 'Europe/London',
            }),
            'runtime.resolve_local_datetime' => _success({
              'requested_local_datetime': '2026-10-25T01:30:00',
              'resolved_local_datetime': '2026-10-25T01:30:00',
              'utc_instant': '2026-10-25T00:30:00Z',
              'timezone': 'Europe/London',
              'resolution': 'fold_earlier',
            }),
            'runtime.localize_instants' => _success({
              'timezone': 'Europe/London',
              'items': [
                {
                  'instant': '2026-03-29T01:00:00Z',
                  'local_datetime': '2026-03-29T02:00:00',
                },
                {
                  'instant': '2026-03-29T01:00:00Z',
                  'local_datetime': '2026-03-29T02:00:00',
                },
              ],
            }),
            _ => throw MissingPluginException(),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'adapter invokes all runtime methods with exact snake_case payloads',
    () async {
      final adapter = MethodChannelTimezoneAdapter(channel: channel);

      final device = await adapter.getDeviceTimezone();
      final resolved = await adapter.resolveLocalDateTime(
        ResolveLocalDateTimeRequestDto(
          localDateTime: LocalWallDateTime.parse('2026-10-25T01:30:00'),
          timezone: 'Europe/London',
        ),
      );
      final localized = await adapter.localizeInstants(
        LocalizeInstantsRequestDto(
          timezone: 'Europe/London',
          instants: [
            DateTime.parse('2026-03-29T01:00:00Z'),
            DateTime.parse('2026-03-29T01:00:00Z'),
          ],
        ),
      );

      expect(device.result.data!.timezone, 'Europe/London');
      expect(
        resolved.result.data!.resolution,
        LocalDateTimeResolution.foldEarlier,
      );
      expect(localized.result.data!.items, hasLength(2));
      expect(calls.map((call) => call.method), [
        'runtime.device_timezone',
        'runtime.resolve_local_datetime',
        'runtime.localize_instants',
      ]);
      expect(calls[0].arguments, <String, dynamic>{});
      expect(calls[1].arguments, {
        'local_datetime': '2026-10-25T01:30:00',
        'timezone': 'Europe/London',
      });
      expect(calls[2].arguments, {
        'timezone': 'Europe/London',
        'instants': ['2026-03-29T01:00:00Z', '2026-03-29T01:00:00Z'],
      });
    },
  );
}

Map<String, dynamic> _success(Map<String, dynamic> data) {
  return {
    'ok': true,
    'data': data,
    'error': null,
    'contract_version': 2,
    'request_id': 'timezone-test',
  };
}
