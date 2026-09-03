import 'package:excellent_calendar/gateway_interfaces/search_gateway.dart';
import 'package:excellent_calendar/gateway_interfaces/search_history_gateway.dart';
import 'package:excellent_calendar/native_contract/search/search_request_dtos.dart';
import 'package:excellent_calendar/native_contract/search/search_response_dtos.dart';

typedef SearchQueryHandler =
    Future<SearchQueryResponseDto> Function(SearchQueryRequestDto request);
typedef SearchHistoryReplaceHandler =
    Future<SearchHistoryResponseDto> Function(
      ReplaceSearchHistoryRequestDto request,
    );
typedef SearchHistoryGetHandler = Future<SearchHistoryResponseDto> Function();

class FakeSearchGateway implements SearchGateway, SearchHistoryGateway {
  FakeSearchGateway({
    required this.onQuery,
    SearchHistoryResponseDto? initialHistory,
    this.onGetHistory,
    this.onReplace,
  }) : _history =
           initialHistory ??
           SearchHistoryResponseDto(revision: 0, items: const []);

  final SearchQueryHandler onQuery;
  final SearchHistoryGetHandler? onGetHistory;
  final SearchHistoryReplaceHandler? onReplace;
  SearchHistoryResponseDto _history;
  final List<SearchQueryRequestDto> queryRequests = [];
  final List<ReplaceSearchHistoryRequestDto> historyRequests = [];
  int historyReads = 0;

  @override
  Future<SearchQueryResponseDto> query(SearchQueryRequestDto request) {
    queryRequests.add(request);
    return onQuery(request);
  }

  @override
  Future<SearchHistoryResponseDto> getLocalHistory() async {
    historyReads += 1;
    final handler = onGetHistory;
    if (handler != null) {
      _history = await handler();
    }
    return _history;
  }

  @override
  Future<SearchHistoryResponseDto> replaceLocalHistory(
    ReplaceSearchHistoryRequestDto request,
  ) async {
    historyRequests.add(request);
    final handler = onReplace;
    if (handler != null) {
      final result = await handler(request);
      _history = result;
      return result;
    }
    if (request.expectedRevision != _history.revision) {
      throw const SearchGatewayFailure(
        code: 'SEARCH_HISTORY_CONFLICT',
        message: 'conflict',
        retryable: true,
      );
    }
    _history = SearchHistoryResponseDto(
      revision:
          _history.revision +
          (request.items.toString() == _history.items.toString() ? 0 : 1),
      items: request.items,
    );
    return _history;
  }
}
