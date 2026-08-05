import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_timezone_adapter.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/native_contract/runtime/localize_instants_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/resolve_local_datetime_dto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'formal Flutter Kotlin JNI C++ chain resolves and localizes London DST',
    (_) async {
      final gateway = MethodChannelTimezoneAdapter();

      final deviceTimezone = await gateway.getDeviceTimezone();
      expect(deviceTimezone.result.ok, isTrue);
      expect(deviceTimezone.result.data!.timezone, isNotEmpty);
      final deviceZoneResolution = await gateway.resolveLocalDateTime(
        ResolveLocalDateTimeRequestDto(
          localDateTime: LocalWallDateTime.parse('2026-02-01T12:00:00'),
          timezone: deviceTimezone.result.data!.timezone,
        ),
      );
      expect(deviceZoneResolution.result.ok, isTrue);

      final gap = await gateway.resolveLocalDateTime(
        ResolveLocalDateTimeRequestDto(
          localDateTime: LocalWallDateTime.parse('2026-03-29T01:30:00'),
          timezone: 'Europe/London',
        ),
      );
      expect(gap.result.ok, isTrue);
      expect(gap.result.data!.resolution, LocalDateTimeResolution.gapShifted);
      expect(
        gap.result.data!.resolvedLocalDateTime.toString(),
        '2026-03-29T02:00:00',
      );
      expect(
        gap.result.data!.utcInstant,
        DateTime.parse('2026-03-29T01:00:00Z'),
      );

      final fold = await gateway.resolveLocalDateTime(
        ResolveLocalDateTimeRequestDto(
          localDateTime: LocalWallDateTime.parse('2026-10-25T01:30:00'),
          timezone: 'Europe/London',
        ),
      );
      expect(fold.result.ok, isTrue);
      expect(fold.result.data!.resolution, LocalDateTimeResolution.foldEarlier);
      expect(
        fold.result.data!.utcInstant,
        DateTime.parse('2026-10-25T00:30:00Z'),
      );

      final localized = await gateway.localizeInstants(
        LocalizeInstantsRequestDto(
          timezone: 'Europe/London',
          instants: [
            DateTime.parse('2026-10-25T00:30:00Z'),
            DateTime.parse('2026-10-25T01:30:00Z'),
            DateTime.parse('2026-10-25T00:30:00Z'),
          ],
        ),
      );
      expect(localized.result.ok, isTrue);
      expect(
        localized.result.data!.items.map(
          (item) => item.localDateTime.toString(),
        ),
        ['2026-10-25T01:30:00', '2026-10-25T01:30:00', '2026-10-25T01:30:00'],
      );
      expect(localized.result.data!.items.map((item) => item.instant), [
        DateTime.parse('2026-10-25T00:30:00Z'),
        DateTime.parse('2026-10-25T01:30:00Z'),
        DateTime.parse('2026-10-25T00:30:00Z'),
      ]);
    },
  );
}
