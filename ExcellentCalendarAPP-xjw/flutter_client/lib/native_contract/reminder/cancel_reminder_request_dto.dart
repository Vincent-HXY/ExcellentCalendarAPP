class CancelReminderRequestDto {
  const CancelReminderRequestDto({required this.id, this.reason});

  final String id;
  final String? reason;

  Map<String, dynamic> toJson() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'CancelReminderRequest.id must be non-empty.',
      );
    }
    return {'id': id, 'reason': reason};
  }
}
