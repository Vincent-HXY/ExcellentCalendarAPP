import 'package:excellent_calendar/application/category/category_models.dart';
import 'package:excellent_calendar/gateway_interfaces/category_repository.dart';
import 'package:excellent_calendar/native_contract/search/search_contract_enums.dart';
import 'package:excellent_calendar/native_contract/search/search_request_dtos.dart';
import 'package:excellent_calendar/native_contract/search/search_response_dtos.dart';
import 'package:excellent_calendar/native_contract/search/search_text_contract.dart';

const searchTimezone = 'Asia/Shanghai';
const searchSnapshot = 'srchsnap1.ABCDEFGHIJKLMNOPQRST';
const searchCursor = 'srchcur1.ABCDEFGHIJKLMNOPQRST';

class FakeSearchCategoryRepository implements CategoryRepository {
  FakeSearchCategoryRepository({this.categories = const []});
  final List<Category> categories;
  @override
  Future<List<Category>> listActiveCategories() async => categories;
  @override
  Future<Category> createCategory(CreateCategoryCommand command) =>
      throw UnimplementedError();
}

SearchQueryResponseDto searchResponse(
  SearchQueryRequestDto request, {
  Map<SearchTargetType, List<SearchItemDto>> items = const {},
  Map<SearchTargetType, int> totals = const {},
  Set<SearchTargetType> hasMore = const {},
  String snapshot = searchSnapshot,
}) => SearchQueryResponseDto(
  queryGeneration: request.queryGeneration,
  normalizedKeyword: SearchTextContract.analyze(
    request.keyword,
  ).normalizedDisplay,
  timezone: request.timezone,
  evaluatedAt: DateTime.utc(2026, 8, 31, 8),
  snapshotToken: snapshot,
  sections: [
    for (final section in request.sections)
      SearchSectionResponseDto(
        targetType: section.targetType,
        items: items[section.targetType] ?? const [],
        totalCount:
            totals[section.targetType] ??
            (items[section.targetType]?.length ?? 0),
        hasMore: hasMore.contains(section.targetType),
        nextCursor: hasMore.contains(section.targetType) ? searchCursor : null,
      ),
  ],
);

SearchEventItemDto searchEvent(int index, {String title = '项目会议'}) =>
    SearchEventItemDto(
      targetId: _uuid(index),
      title: '$title $index',
      match: const SearchMatchDto(
        primaryField: SearchMatchedField.title,
        matchedFields: [SearchMatchedField.title],
        snippet: null,
      ),
      category: null,
      updatedAt: DateTime.utc(2026, 8, 31, 7),
      status: SearchEventStatus.pending,
      isAllDay: false,
      isRecurring: false,
      occurAt: DateTime.utc(2026, 9, 1, index % 23),
      occurDate: null,
      location: null,
      recurrenceRevision: null,
      occurrenceKey: null,
    );

SearchHabitItemDto searchHabit(int index) => SearchHabitItemDto(
  targetId: _uuid(1000 + index),
  title: '晨间复盘 $index',
  match: const SearchMatchDto(
    primaryField: SearchMatchedField.description,
    matchedFields: [SearchMatchedField.description],
    snippet: SearchSnippetDto(
      field: SearchMatchedField.description,
      text: '整理项目会议记录',
      prefixTruncated: false,
      suffixTruncated: false,
    ),
  ),
  category: null,
  updatedAt: DateTime.utc(2026, 8, 31, 7),
  lifecycleStatus: SearchHabitLifecycle.active,
  occurDate: '2026-08-31',
  challengeStartDate: '2026-08-01',
  challengeEndDate: '2026-09-30',
  endedDate: null,
  remainingDays: 31,
  targetCountHundredths: null,
  unit: null,
);

SearchAnniversaryItemDto searchAnniversary(int index) =>
    SearchAnniversaryItemDto(
      targetId: _uuid(2000 + index),
      title: '项目周年 $index',
      match: const SearchMatchDto(
        primaryField: SearchMatchedField.title,
        matchedFields: [SearchMatchedField.title],
        snippet: null,
      ),
      category: null,
      updatedAt: DateTime.utc(2026, 8, 31, 7),
      occurrenceKey: _uuid(3000 + index),
      occurDate: '2026-09-01',
      sourceDate: '2020-09-01',
      isRepeating: true,
      relation: SearchAnniversaryRelation.remaining,
      days: 1,
      yearsElapsed: 6,
    );

String _uuid(int value) {
  final tail = value.toString().padLeft(12, '0');
  return '11111111-1111-4111-8111-$tail';
}
