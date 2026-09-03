import 'package:excellent_calendar/application/search/search_date_filter.dart';
import 'package:excellent_calendar/native_contract/shared/civil_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'presets use natural-day half-open ranges across month and leap year',
    () {
      const leapDay = CivilDate(2028, 2, 29);
      final past = SearchDateFilter.preset(
        SearchDatePreset.pastSevenDays,
        leapDay,
      );
      final future = SearchDateFilter.preset(
        SearchDatePreset.nextSevenDays,
        leapDay,
      );
      final month = SearchDateFilter.preset(
        SearchDatePreset.thisMonth,
        leapDay,
      );

      expect(past.dateFrom, '2028-02-23');
      expect(past.dateToExclusive, '2028-03-01');
      expect(future.dateFrom, '2028-02-29');
      expect(future.dateToExclusive, '2028-03-07');
      expect(month.dateFrom, '2028-02-01');
      expect(month.dateToExclusive, '2028-03-01');
    },
  );

  test(
    'custom inclusive end becomes exclusive and remains fixed when rebased',
    () {
      final custom = SearchDateFilter.custom(
        from: const CivilDate(2026, 12, 30),
        toInclusive: const CivilDate(2027, 1, 2),
      );
      expect(custom.dateFrom, '2026-12-30');
      expect(custom.dateToExclusive, '2027-01-03');
      expect(custom.rebase(const CivilDate(2030, 1, 1)), same(custom));
    },
  );

  test('reversed custom ranges fail explicitly', () {
    expect(
      () => SearchDateFilter.custom(
        from: const CivilDate(2026, 9, 2),
        toInclusive: const CivilDate(2026, 9, 1),
      ),
      throwsFormatException,
    );
  });
}
