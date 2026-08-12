enum AnniversaryCalendarTypeContract {
  solar('solar'),
  lunar('lunar');

  const AnniversaryCalendarTypeContract(this.wireValue);
  final String wireValue;

  static AnniversaryCalendarTypeContract fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () =>
            throw FormatException('Unknown Anniversary calendar_type: $value'),
      );
}

enum AnniversaryImportanceContract {
  unimportantNotUrgent('unimportant_noturgent'),
  importantNotUrgent('important_noturgent'),
  unimportantUrgent('unimportant_urgent'),
  importantUrgent('important_urgent');

  const AnniversaryImportanceContract(this.wireValue);
  final String wireValue;

  static AnniversaryImportanceContract fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () =>
            throw FormatException('Unknown Anniversary importance: $value'),
      );
}

enum AnniversaryCountdownRelationContract {
  remaining('remaining'),
  elapsed('elapsed'),
  today('today');

  const AnniversaryCountdownRelationContract(this.wireValue);
  final String wireValue;

  static AnniversaryCountdownRelationContract fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown Anniversary countdown relation: $value',
        ),
      );
}

enum AnniversarySortByContract {
  targetOccurrenceDate('target_occurrence_date'),
  countdownDays('countdown_days');

  const AnniversarySortByContract(this.wireValue);
  final String wireValue;
}

enum AnniversarySortDirectionContract {
  ascending('asc'),
  descending('desc');

  const AnniversarySortDirectionContract(this.wireValue);
  final String wireValue;
}
