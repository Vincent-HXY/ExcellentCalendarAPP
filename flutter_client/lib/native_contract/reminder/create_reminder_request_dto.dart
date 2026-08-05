import 'reminder_contract_enums.dart';
import '../shared/contract_value.dart';

class CreateReminderRequestDto {
  const CreateReminderRequestDto({
    required this.targetType,
    required this.targetId,
    required this.methods,
    required this.source,
    this.remindAt,
    this.advanceMinutes,
    this.message,
  });

  final ReminderTargetType targetType;
  final String targetId;
  final DateTime? remindAt;
  final int? advanceMinutes;
  final List<ReminderMethod> methods;
  final String? message;
  final ReminderSource source;

  Map<String, dynamic> toJson() {
    if (targetId.trim().isEmpty) {
      throw const FormatException(
        'CreateReminderRequest.target_id must be non-empty.',
      );
    }
    if ((remindAt == null) == (advanceMinutes == null)) {
      throw const FormatException(
        'CreateReminderRequest requires exactly one reminder time form.',
      );
    }
    if (advanceMinutes != null && advanceMinutes! < 0) {
      throw const FormatException(
        'CreateReminderRequest.advance_minutes must be non-negative.',
      );
    }
    if (methods.isEmpty) {
      throw const FormatException(
        'CreateReminderRequest.methods must not be empty.',
      );
    }
    final methodValues = methods.map((method) => method.wireValue).toList();
    if (methodValues.toSet().length != methodValues.length) {
      throw const FormatException(
        'CreateReminderRequest.methods must contain unique values.',
      );
    }

    return {
      'target_type': targetType.wireValue,
      'target_id': targetId,
      'remind_at': remindAt == null
          ? null
          : ContractValue.formatUtcDateTime(
              remindAt!,
              field: 'CreateReminderRequest.remind_at',
            ),
      'advance_minutes': advanceMinutes,
      'methods': methodValues,
      'message': message,
      'is_enabled': true,
      'source': source.wireValue,
    };
  }
}
