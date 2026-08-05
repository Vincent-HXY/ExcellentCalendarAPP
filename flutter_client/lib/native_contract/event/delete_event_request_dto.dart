class DeleteEventRequestDto {
  const DeleteEventRequestDto({
    required this.id,
    this.deleteMode = 'soft',
    this.recurrenceDeleteScope,
    this.expectedRecurrenceRevision,
    this.reason,
  });

  final String id;
  final String deleteMode;
  final String? recurrenceDeleteScope;
  final int? expectedRecurrenceRevision;
  final String? reason;

  Map<String, dynamic> toJson() {
    if (id.trim().isEmpty) {
      throw const FormatException('DeleteEventRequest.id must be non-empty.');
    }
    if (deleteMode != 'soft' && deleteMode != 'hard') {
      throw FormatException('Unknown DeleteMode: $deleteMode');
    }
    if (recurrenceDeleteScope != null &&
        recurrenceDeleteScope != 'all_occurrences') {
      throw FormatException(
        'Unknown RecurrenceDeleteScope: $recurrenceDeleteScope',
      );
    }
    if (expectedRecurrenceRevision != null && expectedRecurrenceRevision! < 1) {
      throw const FormatException(
        'DeleteEventRequest.expected_recurrence_revision must be positive.',
      );
    }
    return {
      'id': id,
      'delete_mode': deleteMode,
      'recurrence_delete_scope': recurrenceDeleteScope,
      'expected_recurrence_revision': expectedRecurrenceRevision,
      'reason': reason,
    };
  }
}
