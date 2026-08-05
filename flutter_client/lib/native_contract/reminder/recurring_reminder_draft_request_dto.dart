import 'reminder_draft_request_dto.dart';

class RecurringReminderDraftRequestDto implements EventReminderDraftRequestDto {
  const RecurringReminderDraftRequestDto({
    required this.advanceMinutes,
    this.targetId,
    this.message,
    this.source = 'manual',
  });

  final int advanceMinutes;
  final String? targetId;
  final String? message;
  final String source;

  ReminderDraftRequestDto get _delegate => ReminderDraftRequestDto(
    targetType: 'event',
    targetId: targetId,
    advanceMinutes: advanceMinutes,
    methods: const ['popup'],
    message: message,
    source: source,
  );

  @override
  Map<String, dynamic> toJson() => _delegate.toEventJson(recurring: true);

  @override
  Map<String, dynamic> toEventJson({required bool recurring}) {
    if (!recurring) {
      throw const FormatException(
        'RecurringReminderDraftRequest requires a recurring Event.',
      );
    }
    return toJson();
  }
}
