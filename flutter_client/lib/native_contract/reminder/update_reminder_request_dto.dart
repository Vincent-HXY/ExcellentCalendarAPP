import '../shared/contract_field.dart';
import '../shared/contract_value.dart';
import 'reminder_contract_enums.dart';

class UpdateReminderRequestDto {
  const UpdateReminderRequestDto({
    required this.reminderId,
    this.targetType,
    this.targetId,
    this.remindAt = const ContractField<DateTime>.absent(),
    this.advanceMinutes = const ContractField<int>.absent(),
    this.methods,
    this.message = const ContractField<String>.absent(),
    this.source,
  });

  UpdateReminderRequestDto.useAbsoluteTime({
    required this.reminderId,
    required DateTime value,
  }) : targetType = null,
       targetId = null,
       remindAt = ContractField<DateTime>.value(value),
       advanceMinutes = const ContractField<int>.value(null),
       methods = null,
       message = const ContractField<String>.absent(),
       source = null;

  UpdateReminderRequestDto.useAdvanceMinutes({
    required this.reminderId,
    required int value,
  }) : targetType = null,
       targetId = null,
       remindAt = const ContractField<DateTime>.value(null),
       advanceMinutes = ContractField<int>.value(value),
       methods = null,
       message = const ContractField<String>.absent(),
       source = null;

  final String reminderId;
  final ReminderTargetType? targetType;
  final String? targetId;
  final ContractField<DateTime> remindAt;
  final ContractField<int> advanceMinutes;
  final List<ReminderMethod>? methods;
  final ContractField<String> message;
  final ReminderSource? source;

  Map<String, dynamic> toJson() {
    if (reminderId.trim().isEmpty) {
      throw const FormatException(
        'UpdateReminderRequest.reminder_id must be non-empty.',
      );
    }
    if (targetId != null && targetId!.trim().isEmpty) {
      throw const FormatException(
        'UpdateReminderRequest.target_id must be non-empty.',
      );
    }
    final advance = advanceMinutes.value;
    if (advanceMinutes.isPresent && advance != null && advance < 0) {
      throw const FormatException(
        'UpdateReminderRequest.advance_minutes must be non-negative.',
      );
    }
    final methodValues = methods
        ?.map((method) => method.wireValue)
        .toList(growable: false);
    if (methodValues != null &&
        (methodValues.isEmpty ||
            methodValues.toSet().length != methodValues.length)) {
      throw const FormatException('UpdateReminderRequest.methods is invalid.');
    }
    final json = <String, dynamic>{'reminder_id': reminderId};
    if (targetType != null) json['target_type'] = targetType!.wireValue;
    if (targetId != null) json['target_id'] = targetId;
    if (remindAt.isPresent) {
      json['remind_at'] = remindAt.value == null
          ? null
          : ContractValue.formatUtcDateTime(
              remindAt.value!,
              field: 'UpdateReminderRequest.remind_at',
            );
    }
    if (advanceMinutes.isPresent) {
      json['advance_minutes'] = advance;
    }
    if (methodValues != null) json['methods'] = methodValues;
    if (message.isPresent) json['message'] = message.value;
    if (source != null) json['source'] = source!.wireValue;
    return json;
  }
}
