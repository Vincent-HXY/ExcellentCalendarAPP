import 'dart:async';

import 'package:excellent_calendar/application/search/search_controller.dart';
import 'package:excellent_calendar/application/search/search_date_filter.dart';
import 'package:excellent_calendar/application/search/search_models.dart';
import 'package:excellent_calendar/gateway_interfaces/search_gateway.dart';
import 'package:excellent_calendar/native_contract/search/search_contract_enums.dart';
import 'package:excellent_calendar/native_contract/search/search_request_dtos.dart';
import 'package:excellent_calendar/native_contract/search/search_response_dtos.dart';
import 'package:excellent_calendar/native_contract/search/search_text_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_search_gateway.dart';
import 'support/search_test_support.dart';

void main() {
  test(
    'debounces one committed character and whitespace never queries',
    () async {
      final gateway = _emptyGateway();
      final controller = _controller(
        gateway,
        debounce: const Duration(milliseconds: 30),
      );
      addTearDown(controller.dispose);
      await controller.setActive(true);

      controller.updateText('项', isComposing: false);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(gateway.queryRequests, isEmpty);
      controller.updateText('项目', isComposing: false);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(gateway.queryRequests, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(gateway.queryRequests.single.keyword, '项目');

      controller.updateText('  ', isComposing: false);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(gateway.queryRequests, hasLength(1));
      expect(controller.state.contentPhase, SearchContentPhase.history);
    },
  );

  test('IME pending keyboard submit waits for composition commit', () async {
    final gateway = _emptyGateway();
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await controller.setActive(true);

    controller.updateText('xiang', isComposing: true);
    final pending = controller.submit();
    await _flush();
    expect(controller.state.pendingKeyboardSubmit, isTrue);
    expect(gateway.queryRequests, isEmpty);

    controller.updateText('项目', isComposing: false);
    await pending;
    await _flush();
    expect(gateway.queryRequests.single.keyword, '项目');
    expect(controller.state.pendingKeyboardSubmit, isFalse);
  });

  test('A-B-C out-of-order responses only accept C', () async {
    final completers = <String, Completer<SearchQueryResponseDto>>{};
    final gateway = FakeSearchGateway(
      onQuery: (request) {
        final completer = Completer<SearchQueryResponseDto>();
        completers[request.keyword] = completer;
        return completer.future;
      },
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await controller.setActive(true);

    controller.updateText('A', isComposing: false);
    final a = controller.submit();
    await _flush();
    controller.updateText('B', isComposing: false);
    final b = controller.submit();
    await _flush();
    controller.updateText('C', isComposing: false);
    final c = controller.submit();
    await _flush();

    final cRequest = gateway.queryRequests.last;
    completers['C']!.complete(searchResponse(cRequest));
    await c;
    completers['A']!.complete(searchResponse(gateway.queryRequests[0]));
    completers['B']!.complete(searchResponse(gateway.queryRequests[1]));
    await Future.wait([a, b]);

    expect(controller.state.normalizedKeyword, 'C');
    expect(controller.state.displayedFingerprint, startsWith('C|'));
  });

  test(
    'independent pagination accepts 21 items and blocks duplicate identity',
    () async {
      var duplicate = false;
      final gateway = FakeSearchGateway(
        onQuery: (request) async {
          if (request.sections.single.cursor == null) {
            return searchResponse(
              request,
              items: {
                SearchTargetType.event: [
                  for (var i = 1; i <= 20; i++) searchEvent(i),
                ],
              },
              totals: const {SearchTargetType.event: 21},
              hasMore: const {SearchTargetType.event},
            );
          }
          return searchResponse(
            request,
            items: {
              SearchTargetType.event: [searchEvent(duplicate ? 1 : 21)],
            },
            totals: const {SearchTargetType.event: 21},
          );
        },
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await controller.setActive(true);
      await controller.applyFilters(
        SearchFilters(targetTypes: {SearchTargetType.event}),
      );
      controller.updateText('项目', isComposing: false);
      await controller.submit();
      await controller.loadMore(SearchTargetType.event);
      expect(
        controller.state.section(SearchTargetType.event).items,
        hasLength(21),
      );
      expect(controller.state.section(SearchTargetType.event).hasMore, isFalse);

      duplicate = true;
      controller.updateText('会议', isComposing: false);
      await controller.submit();
      await controller.loadMore(SearchTargetType.event);
      expect(
        controller.state.section(SearchTargetType.event).phase,
        SearchSectionPhase.contractError,
      );
      expect(
        controller.state.section(SearchTargetType.event).items,
        hasLength(20),
      );
    },
  );

  for (final total in [0, 1, 19, 20, 21, 41, 101]) {
    test('event pagination conserves all $total unique items', () async {
      final gateway = FakeSearchGateway(
        onQuery: (request) async => _pagedEventResponse(request, total),
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await controller.setActive(true);
      await controller.applyFilters(
        SearchFilters(targetTypes: {SearchTargetType.event}),
      );
      controller.updateText('项目', isComposing: false);
      await controller.submit();
      while (controller.state.section(SearchTargetType.event).hasMore) {
        await controller.loadMore(SearchTargetType.event);
      }
      final items = controller.state.section(SearchTargetType.event).items;
      expect(items, hasLength(total));
      expect(items.map((item) => item.identityKey).toSet(), hasLength(total));
      expect(
        gateway.queryRequests.every(
          (request) => request.sections.single.pageSize == searchPageSize,
        ),
        isTrue,
      );
    });
  }

  test(
    'keyboard success records canonical history but debounce does not',
    () async {
      final gateway = _emptyGateway();
      final controller = _controller(
        gateway,
        debounce: const Duration(milliseconds: 5),
      );
      addTearDown(controller.dispose);
      await controller.setActive(true);

      controller.updateText('自动', isComposing: false);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(gateway.historyRequests, isEmpty);

      controller.updateText('手动', isComposing: false);
      await controller.submit();
      await _flush();
      expect(gateway.historyRequests.single.items, ['手动']);
    },
  );

  test('U+FEFF remains a searchable non-whitespace scalar', () async {
    final gateway = _emptyGateway();
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await controller.setActive(true);

    controller.updateText('\uFEFF', isComposing: false);
    await controller.submit();

    expect(gateway.queryRequests.single.keyword, '\uFEFF');
    expect(controller.state.contentPhase, SearchContentPhase.empty);
  });

  test(
    'history conflict reloads and replays intent over the latest order',
    () async {
      var replaceCalls = 0;
      var historyReads = 0;
      final gateway = FakeSearchGateway(
        initialHistory: SearchHistoryResponseDto(
          revision: 3,
          items: const ['alpha'],
        ),
        onGetHistory: () async {
          historyReads += 1;
          return historyReads == 1
              ? SearchHistoryResponseDto(revision: 3, items: const ['alpha'])
              : SearchHistoryResponseDto(
                  revision: 4,
                  items: const ['gamma', 'alpha'],
                );
        },
        onQuery: (request) async => searchResponse(request),
        onReplace: (request) async {
          replaceCalls += 1;
          if (replaceCalls == 1) {
            throw const SearchGatewayFailure(
              code: 'SEARCH_HISTORY_CONFLICT',
              message: 'conflict',
              retryable: true,
            );
          }
          return SearchHistoryResponseDto(revision: 5, items: request.items);
        },
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await controller.setActive(true);

      await controller.selectHistory('beta');
      await _flush();
      await _flush();
      expect(replaceCalls, 2);
      expect(gateway.historyRequests.last.items, ['beta', 'gamma', 'alpha']);
      expect(controller.state.history.items, ['beta', 'gamma', 'alpha']);
      expect(controller.state.history.revision, 5);
    },
  );

  test(
    'history write failure rolls back UI without cancelling the query',
    () async {
      final gateway = FakeSearchGateway(
        initialHistory: SearchHistoryResponseDto(
          revision: 2,
          items: const ['已保存'],
        ),
        onQuery: (request) async => searchResponse(request),
        onReplace: (_) async => throw const SearchGatewayFailure(
          code: 'SEARCH_HISTORY_STORAGE_FAILED',
          message: 'disk full',
          retryable: false,
        ),
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await controller.setActive(true);

      await controller.selectHistory('继续搜索');
      await _flush();
      expect(gateway.queryRequests.single.keyword, '继续搜索');
      expect(controller.state.contentPhase, SearchContentPhase.empty);
      expect(controller.state.history.items, ['已保存']);
      expect(
        controller.state.history.writePhase,
        SearchHistoryWritePhase.error,
      );
    },
  );

  test(
    'timezone resume invalidates cursors and refreshes the current query once',
    () async {
      var timezone = searchTimezone;
      final gateway = _emptyGateway();
      final controller = _controller(gateway, timezone: () async => timezone);
      addTearDown(controller.dispose);
      await controller.setActive(true);
      controller.updateText('项目', isComposing: false);
      await controller.submit();
      await controller.setActive(false);

      timezone = 'Europe/Paris';
      await controller.setActive(true);
      expect(controller.state.timezone, 'Europe/Paris');
      expect(gateway.queryRequests.last.timezone, 'Europe/Paris');
      expect(
        controller.state.sections.values.every(
          (section) => section.nextCursor == null,
        ),
        isTrue,
      );
    },
  );

  test('detail outcomes refresh only changed/deleted section', () async {
    final gateway = _emptyGateway();
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await controller.setActive(true);
    controller.updateText('项目', isComposing: false);
    await controller.submit();
    final before = gateway.queryRequests.length;

    await controller.refreshAfterDetail(
      SearchTargetType.event,
      SearchDetailMutation.unchanged,
    );
    expect(gateway.queryRequests, hasLength(before));
    await controller.refreshAfterDetail(
      SearchTargetType.habit,
      SearchDetailMutation.changed,
    );
    expect(
      gateway.queryRequests.last.sections.single.targetType,
      SearchTargetType.habit,
    );
  });
}

FakeSearchGateway _emptyGateway() =>
    FakeSearchGateway(onQuery: (request) async => searchResponse(request));

SearchController _controller(
  FakeSearchGateway gateway, {
  Duration debounce = const Duration(seconds: 1),
  Future<String> Function()? timezone,
}) => SearchController(
  gateway: gateway,
  historyGateway: gateway,
  timezoneProvider: timezone ?? () async => searchTimezone,
  categoryRepository: FakeSearchCategoryRepository(),
  nowProvider: () => DateTime(2026, 8, 31, 9),
  debounceDuration: debounce,
  clockGuardInterval: const Duration(days: 1),
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

SearchQueryResponseDto _pagedEventResponse(
  SearchQueryRequestDto request,
  int total,
) {
  final cursor = request.sections.single.cursor;
  final offset = cursor == null
      ? 0
      : int.parse(cursor.substring('srchcur1.'.length));
  final count = (total - offset).clamp(0, searchPageSize);
  final nextOffset = offset + count;
  final hasMore = nextOffset < total;
  return SearchQueryResponseDto(
    queryGeneration: request.queryGeneration,
    normalizedKeyword: SearchTextContract.analyze(
      request.keyword,
    ).normalizedDisplay,
    timezone: request.timezone,
    evaluatedAt: DateTime.utc(2026, 8, 31, 8),
    snapshotToken: searchSnapshot,
    sections: [
      SearchSectionResponseDto(
        targetType: SearchTargetType.event,
        items: [
          for (var index = offset + 1; index <= nextOffset; index++)
            searchEvent(index),
        ],
        totalCount: total,
        hasMore: hasMore,
        nextCursor: hasMore
            ? 'srchcur1.${nextOffset.toString().padLeft(20, '0')}'
            : null,
      ),
    ],
  );
}
