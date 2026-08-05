class CancelReminderRequestDto {
  const CancelReminderRequestDto({required this.reminderId});

  final String reminderId;

  Map<String, dynamic> toJson() {
    if (reminderId.trim().isEmpty) {
      throw const FormatException(
        'CancelReminderRequest.reminder_id must be non-empty.',
      );
    }
    return {'reminder_id': reminderId};
  }
}
