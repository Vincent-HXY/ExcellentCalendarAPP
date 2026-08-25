import '../../gateway_interfaces/anniversary_occurrence_gateway.dart';
import 'anniversary_models.dart';
import 'anniversary_occurrence_models.dart';

class ListAnniversaryOccurrencesUseCase {
  const ListAnniversaryOccurrencesUseCase(this._gateway);

  final AnniversaryOccurrenceGateway _gateway;

  Future<List<AnniversaryOccurrenceSummary>> call(
    AnniversaryOccurrenceQuery query,
  ) async {
    _validateQuery(query);
    final items = <AnniversaryOccurrenceSummary>[];
    final identities = <String>{};
    final cursors = <String>{};
    AnniversaryOccurrenceSummary? previous;
    String? cursor;

    do {
      final page = await _gateway.listOccurrencePage(
        AnniversaryOccurrencePageQuery(query: query, cursor: cursor),
      );
      for (final item in page.items) {
        final identity = '${item.anniversaryId}|${item.occurrenceKey}';
        if (!identities.add(identity)) {
          throw const AnniversaryGatewayException(
            AnniversaryFailureCode.contractValidation,
            debugMessage: 'Anniversary occurrence page contains duplicates.',
          );
        }
        if (previous != null && _compare(previous, item) >= 0) {
          throw const AnniversaryGatewayException(
            AnniversaryFailureCode.contractValidation,
            debugMessage:
                'Anniversary occurrences are not in strict stable order.',
          );
        }
        items.add(item);
        previous = item;
      }
      if (page.hasMore) {
        final next = page.nextCursor;
        if (next == null || !cursors.add(next)) {
          throw const AnniversaryGatewayException(
            AnniversaryFailureCode.contractValidation,
            debugMessage: 'Anniversary occurrence cursor loop detected.',
          );
        }
        cursor = next;
      } else {
        if (page.nextCursor != null) {
          throw const AnniversaryGatewayException(
            AnniversaryFailureCode.contractValidation,
            debugMessage: 'Terminal Anniversary occurrence page has a cursor.',
          );
        }
        cursor = null;
        break;
      }
    } while (true);

    return List.unmodifiable(items);
  }

  static void _validateQuery(AnniversaryOccurrenceQuery query) {
    final start = DateTime.utc(
      query.rangeStartDate.year,
      query.rangeStartDate.month,
      query.rangeStartDate.day,
    );
    final end = DateTime.utc(
      query.rangeEndDate.year,
      query.rangeEndDate.month,
      query.rangeEndDate.day,
    );
    final days = end.difference(start).inDays;
    if (days < 1 || days > 400 || query.timezone.trim().isEmpty) {
      throw const AnniversaryGatewayException(
        AnniversaryFailureCode.occurrenceQueryInvalid,
      );
    }
    if (query.categoryIds.toSet().length != query.categoryIds.length ||
        query.importance.toSet().length != query.importance.length ||
        query.pageSize < 1 ||
        query.pageSize > 500) {
      throw const AnniversaryGatewayException(
        AnniversaryFailureCode.occurrenceQueryInvalid,
      );
    }
  }

  static int _compare(
    AnniversaryOccurrenceSummary left,
    AnniversaryOccurrenceSummary right,
  ) {
    final date = left.occurrenceDate.compareTo(right.occurrenceDate);
    if (date != 0) return date;
    final anniversary = left.anniversaryId.compareTo(right.anniversaryId);
    if (anniversary != 0) return anniversary;
    return left.occurrenceKey.compareTo(right.occurrenceKey);
  }
}
