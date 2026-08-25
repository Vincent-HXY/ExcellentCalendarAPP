import 'anniversary_models.dart';

class AnniversaryOccurrenceQuery {
  AnniversaryOccurrenceQuery({
    required DateTime rangeStartDate,
    required DateTime rangeEndDate,
    required this.timezone,
    List<String> categoryIds = const [],
    List<AnniversaryImportance> importance = const [],
    this.pageSize = 200,
  }) : rangeStartDate = anniversaryDateOnly(rangeStartDate),
       rangeEndDate = anniversaryDateOnly(rangeEndDate),
       categoryIds = List.unmodifiable(categoryIds),
       importance = List.unmodifiable(importance);

  final DateTime rangeStartDate;
  final DateTime rangeEndDate;
  final String timezone;
  final List<String> categoryIds;
  final List<AnniversaryImportance> importance;
  final int pageSize;
}

class AnniversaryOccurrencePageQuery {
  const AnniversaryOccurrencePageQuery({
    required this.query,
    required this.cursor,
  });

  final AnniversaryOccurrenceQuery query;
  final String? cursor;
}

class AnniversaryOccurrenceSummary {
  AnniversaryOccurrenceSummary({
    required this.anniversaryId,
    required this.occurrenceKey,
    required DateTime occurrenceDate,
    required DateTime sourceDate,
    required this.title,
    required this.calendarType,
    required this.isRepeating,
    required this.yearsElapsed,
    required this.categoryId,
    required this.importance,
    required this.hasActiveReminders,
    required this.reminderCount,
  }) : occurrenceDate = anniversaryDateOnly(occurrenceDate),
       sourceDate = anniversaryDateOnly(sourceDate);

  final String anniversaryId;
  final String occurrenceKey;
  final DateTime occurrenceDate;
  final DateTime sourceDate;
  final String title;
  final AnniversaryCalendarType calendarType;
  final bool isRepeating;
  final int yearsElapsed;
  final String? categoryId;
  final AnniversaryImportance? importance;
  final bool hasActiveReminders;
  final int reminderCount;

  bool get showYearsElapsed => yearsElapsed > 0;
}

class AnniversaryOccurrencePage {
  AnniversaryOccurrencePage({
    required List<AnniversaryOccurrenceSummary> items,
    required this.hasMore,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<AnniversaryOccurrenceSummary> items;
  final bool hasMore;
  final String? nextCursor;
}
