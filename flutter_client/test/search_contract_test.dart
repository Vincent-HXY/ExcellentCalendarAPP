import 'dart:convert';
import 'dart:io';

import 'package:excellent_calendar/native_contract/search/search_contract_enums.dart';
import 'package:excellent_calendar/native_contract/search/search_mapper.dart';
import 'package:excellent_calendar/native_contract/search/search_request_dtos.dart';
import 'package:excellent_calendar/native_contract/search/search_response_dtos.dart';
import 'package:excellent_calendar/presentation/search/widgets/highlighted_search_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses frozen three-type and history fixtures strictly', () {
    final response = SearchMapper.query(
      _fixture('query_response_three_types.valid.json'),
    );
    final history = SearchMapper.history(_fixture('history.valid.json'));

    expect(
      response.sections.map((section) => section.targetType),
      SearchTargetType.values,
    );
    expect(response.sections[0].items.single, isA<SearchEventItemDto>());
    expect(response.sections[1].items.single, isA<SearchHabitItemDto>());
    expect(response.sections[2].items.single, isA<SearchAnniversaryItemDto>());
    expect(history.revision, 3);
    expect(history.items, ['项目 MEETING', '年度回顾']);
  });

  test('request emits the exact frozen snake_case payload', () {
    final request = SearchQueryRequestDto(
      queryGeneration: 7,
      keyword: '  项目　MEETING  ',
      timezone: 'Asia/Shanghai',
      targetTypes: SearchTargetType.values,
      dateFrom: null,
      dateToExclusive: null,
      categoryIds: null,
      includeUncategorized: false,
      includeCompleted: true,
      sortBy: SearchSortBy.relevance,
      sections: [
        for (final type in SearchTargetType.values)
          SearchSectionRequestDto(targetType: type, cursor: null),
      ],
    );
    expect(request.toJson(), _fixture('query_three_sections.valid.json'));
  });

  test('Search text limits count Unicode scalars and preserve U+FEFF', () {
    final emojiKeyword = List.filled(128, '😀').join();
    expect(
      () => SearchQueryRequestDto(
        queryGeneration: 1,
        keyword: emojiKeyword,
        timezone: 'Asia/Shanghai',
        targetTypes: const [SearchTargetType.event],
        dateFrom: null,
        dateToExclusive: null,
        categoryIds: null,
        includeUncategorized: false,
        includeCompleted: false,
        sortBy: SearchSortBy.relevance,
        sections: [
          SearchSectionRequestDto(
            targetType: SearchTargetType.event,
            cursor: null,
          ),
        ],
      ),
      returnsNormally,
    );
    expect(
      () => SearchHistoryResponseDto(revision: 1, items: const ['\uFEFF']),
      returnsNormally,
    );
    expect(
      () => ReplaceSearchHistoryRequestDto(
        expectedRevision: 1,
        items: const ['\uFEFF'],
      ),
      returnsNormally,
    );
    expect(
      () => SearchQueryRequestDto(
        queryGeneration: 1,
        keyword: '$emojiKeyword😀',
        timezone: 'Asia/Shanghai',
        targetTypes: const [SearchTargetType.event],
        dateFrom: null,
        dateToExclusive: null,
        categoryIds: null,
        includeUncategorized: false,
        includeCompleted: false,
        sortBy: SearchSortBy.relevance,
        sections: [
          SearchSectionRequestDto(
            targetType: SearchTargetType.event,
            cursor: null,
          ),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => SearchHistoryResponseDto(revision: 1, items: const ['\uD800']),
      throwsFormatException,
    );
  });

  test('Search text uses only the frozen whitespace set', () {
    expect(
      () => ReplaceSearchHistoryRequestDto(
        expectedRevision: 0,
        items: const ['alpha\u3000beta'],
      ),
      throwsFormatException,
    );
    expect(
      () => ReplaceSearchHistoryRequestDto(
        expectedRevision: 0,
        items: const ['alpha\uFEFFbeta'],
      ),
      returnsNormally,
    );
  });

  test('rejects extra fields, unknown enums and invalid time unions', () {
    final extra = _fixture('query_response_three_types.valid.json')
      ..['extra'] = true;
    expect(() => SearchMapper.query(extra), throwsFormatException);

    final unknown = _fixture('query_response_three_types.valid.json');
    ((unknown['sections'] as List).first
            as Map<String, dynamic>)['target_type'] =
        'task';
    expect(() => SearchMapper.query(unknown), throwsFormatException);

    final union = _fixture('query_response_three_types.valid.json');
    final event =
        (((union['sections'] as List).first as Map<String, dynamic>)['items']
                    as List)
                .first
            as Map<String, dynamic>;
    event['occur_date'] = '2026-09-01';
    expect(() => SearchMapper.query(union), throwsFormatException);
  });

  test(
    'visible highlighter preserves emoji UTF-16 boundaries and merges matches',
    () {
      final ranges = visibleSearchMatchRanges(
        '😀Meeting meeting',
        'MEETING 😀',
      );
      expect(ranges, [
        const TextRange(start: 0, end: 9),
        const TextRange(start: 10, end: 17),
      ]);
      for (final range in ranges) {
        expect(
          () => '😀Meeting meeting'.substring(range.start, range.end),
          returnsNormally,
        );
      }
      expect(visibleSearchMatchRanges('a\uFEFFb', '\uFEFF'), [
        const TextRange(start: 1, end: 2),
      ]);
    },
  );

  test('fixture manifest keeps the complete 31-case revision 2 matrix', () {
    final manifest = _fixture('manifest.json');
    expect(manifest['fixture_version'], 2);
    expect(
      manifest['cases'],
      isA<List>().having((value) => value.length, 'length', 31),
    );
  });

  test(
    'all 31 revision 2 fixtures are consumed by the typed boundary matrix',
    () {
      final manifest = _fixture('manifest.json');
      final cases = manifest['cases']! as List<dynamic>;
      var consumed = 0;
      for (final rawCase in cases) {
        final fixtureCase = Map<String, dynamic>.from(rawCase! as Map);
        final instance = _fixture(fixtureCase['instance']! as String);
        final schema = fixtureCase['schema'] as String?;
        final shouldThrow =
            fixtureCase['expected_valid'] == false ||
            fixtureCase['expected_error'] != null;
        void parse() {
          if (schema == null) return;
          if (schema.endsWith('search_query_request.schema.json')) {
            SearchQueryRequestDto.fromJson(instance);
          } else if (schema.endsWith('search_query_response.schema.json')) {
            SearchMapper.query(instance);
          } else if (schema.endsWith('search_section_response.schema.json')) {
            SearchSectionResponseDto.fromJson(instance);
          } else if (schema.endsWith('search_history_response.schema.json')) {
            SearchMapper.history(instance);
          } else if (schema.endsWith(
            'replace_search_history_request.schema.json',
          )) {
            ReplaceSearchHistoryRequestDto.fromJson(instance);
          }
        }

        if (shouldThrow && schema != null) {
          expect(
            parse,
            throwsFormatException,
            reason: fixtureCase['name']! as String,
          );
        } else {
          expect(
            parse,
            returnsNormally,
            reason: fixtureCase['name']! as String,
          );
        }
        consumed += 1;
      }
      expect(consumed, 31);
    },
  );
}

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('../contracts/fixtures/search/$name').readAsStringSync())
        as Map<String, dynamic>;
