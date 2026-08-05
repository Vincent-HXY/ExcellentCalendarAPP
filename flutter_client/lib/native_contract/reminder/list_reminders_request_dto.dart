import '../common/pagination_request_dto.dart';
import '../shared/contract_value.dart';
import 'reminder_contract_enums.dart';

class ListRemindersRequestDto {
  const ListRemindersRequestDto({
    this.targetType,
    this.targetId,
    this.recurrenceRevision,
    this.occurrenceKey,
    this.remindAtFrom,
    this.remindAtTo,
    this.methods = const [],
    this.status = const [],
    this.isEnabled,
    this.includeDeleted = false,
    this.pagination = const PaginationRequestDto(),
    this.sortBy = 'remind_at',
    this.sortDirection = 'asc',
  });

  static const _sortValues = {
    null,
    'remind_at',
    'created_at',
    'updated_at',
    'status',
    'target_type',
  };

  final ReminderTargetType? targetType;
  final String? targetId;
  final int? recurrenceRevision;
  final String? occurrenceKey;
  final DateTime? remindAtFrom;
  final DateTime? remindAtTo;
  final List<ReminderMethod> methods;
  final List<ReminderStatus> status;
  final bool? isEnabled;
  final bool includeDeleted;
  final PaginationRequestDto pagination;
  final String? sortBy;
  final String? sortDirection;

  Map<String, dynamic> toJson() {
    if (recurrenceRevision != null && recurrenceRevision! < 1) {
      throw const FormatException(
        'ListRemindersRequest.recurrence_revision must be positive.',
      );
    }
    if (!_sortValues.contains(sortBy)) {
      throw FormatException('Unknown ListReminders sort_by: $sortBy');
    }
    if (sortDirection != null &&
        sortDirection != 'asc' &&
        sortDirection != 'desc') {
      throw FormatException('Unknown SortDirection: $sortDirection');
    }
    return {
      'target_type': targetType?.wireValue,
      'target_id': targetId,
      'recurrence_revision': recurrenceRevision,
      'occurrence_key': occurrenceKey,
      'remind_at_from': remindAtFrom == null
          ? null
          : ContractValue.formatUtcDateTime(
              remindAtFrom!,
              field: 'ListRemindersRequest.remind_at_from',
            ),
      'remind_at_to': remindAtTo == null
          ? null
          : ContractValue.formatUtcDateTime(
              remindAtTo!,
              field: 'ListRemindersRequest.remind_at_to',
            ),
      'methods': methods.map((method) => method.wireValue).toList(),
      'status': status.map((value) => value.wireValue).toList(),
      'is_enabled': isEnabled,
      'include_deleted': includeDeleted,
      'pagination': pagination.toJson(),
      'sort_by': sortBy,
      'sort_direction': sortDirection,
    };
  }
}
