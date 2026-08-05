import '../shared/contract_value.dart';

abstract interface class EventReminderDraftRequestDto {
  Map<String, dynamic> toJson();

  Map<String, dynamic> toEventJson({required bool recurring});
}

class ReminderDraftRequestDto implements EventReminderDraftRequestDto {
  const ReminderDraftRequestDto({
    required this.targetType,
    required this.methods,
    required this.source,
    this.targetId,
    this.remindAt,
    this.advanceMinutes,
    this.message,
  });

  static const _ordinaryTargetTypes = {'event', 'anniversary'};
  static const _methods = {'ring', 'popup', 'wechat'};
  static const _sources = {
    'manual',
    'auto',
    'ai_extraction',
    'sync',
    'import',
    'wechat',
  };

  final String targetType;
  final String? targetId;
  final DateTime? remindAt;
  final int? advanceMinutes;
  final List<String> methods;
  final String? message;
  final String source;

  @override
  Map<String, dynamic> toJson() => _ordinaryJson();

  @override
  Map<String, dynamic> toEventJson({required bool recurring}) {
    if (!recurring) return _ordinaryJson();
    _validateShared();
    if (targetType != 'event' ||
        remindAt != null ||
        advanceMinutes == null ||
        methods.length != 1 ||
        methods.single != 'popup') {
      throw const FormatException(
        'Recurring Event reminders require advance_minutes and popup only.',
      );
    }
    return {
      'target_type': 'event',
      'target_id': targetId,
      'advance_minutes': advanceMinutes,
      'methods': const ['popup'],
      'message': message,
      'is_enabled': true,
      'source': source,
    };
  }

  Map<String, dynamic> _ordinaryJson() {
    _validateShared();
    ContractValue.validateEnum(
      targetType,
      _ordinaryTargetTypes,
      'ReminderDraftRequest.target_type',
    );
    final hasAbsolute = remindAt != null;
    final hasAdvance = advanceMinutes != null;
    if (hasAbsolute == hasAdvance) {
      throw const FormatException(
        'ReminderDraftRequest requires exactly one reminder time form.',
      );
    }
    return {
      'target_type': targetType,
      'target_id': targetId,
      'remind_at': hasAbsolute
          ? ContractValue.formatUtcDateTime(
              remindAt!,
              field: 'ReminderDraftRequest.remind_at',
            )
          : null,
      'advance_minutes': advanceMinutes,
      'methods': List<String>.unmodifiable(methods),
      'message': message,
      'is_enabled': true,
      'source': source,
    };
  }

  void _validateShared() {
    if (targetId != null && targetId!.trim().isEmpty) {
      throw const FormatException(
        'ReminderDraftRequest.target_id must be non-empty or null.',
      );
    }
    if (advanceMinutes != null && advanceMinutes! < 0) {
      throw const FormatException(
        'ReminderDraftRequest.advance_minutes must be non-negative.',
      );
    }
    if (methods.isEmpty ||
        methods.toSet().length != methods.length ||
        methods.any((method) => !_methods.contains(method))) {
      throw const FormatException('ReminderDraftRequest.methods is invalid.');
    }
    ContractValue.validateEnum(source, _sources, 'ReminderDraftRequest.source');
  }
}
