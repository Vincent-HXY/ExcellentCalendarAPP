// 测试 fixture 集中提供稳定的请求和响应样本，避免每个用例重复拼装大段 Map。
// 修改 Contract 字段时，这些样本也能集中暴露需要同步更新的位置。
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_mapper.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_response_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

// 构造 ReminderResponse 的线格式 Map，可通过参数覆盖当前场景关心的字段。
Map<String, dynamic> reminderResponseJson({
  String id = 'reminder-1',
  String status = 'scheduled',
  bool isEnabled = true,
  String? failureReason,
  String? deletedAt,
}) {
  return {
    'id': id,
    'target_type': 'event',
    'target_id': 'event-1',
    'remind_at': '2026-06-15T02:00:00.000Z',
    'methods': ['ring', 'popup'],
    'advance_minutes': 15,
    'message': 'Meeting reminder',
    'is_enabled': isEnabled,
    'status': status,
    'scheduled_at': status == 'scheduled' ? '2026-06-15T01:00:00.000Z' : null,
    'last_triggered_at': null,
    'failure_reason': failureReason,
    'created_at': '2026-06-15T00:00:00.000Z',
    'updated_at': '2026-06-15T01:00:00.000Z',
    'deleted_at': deletedAt,
  };
}

// 构造“通道正常且业务成功”的调用结果。
NativeInvocation<ReminderResponseDto> reminderSuccessInvocation({
  String status = 'scheduled',
  bool isEnabled = true,
  String? failureReason,
  String? deletedAt,
  String requestId = 'native-request-1',
}) {
  final rawResponse = <String, dynamic>{
    'ok': true,
    'data': reminderResponseJson(
      status: status,
      isEnabled: isEnabled,
      failureReason: failureReason,
      deletedAt: deletedAt,
    ),
    'error': null,
    'contract_version': 1,
    'request_id': requestId,
  };
  return NativeInvocation<ReminderResponseDto>(
    rawResponse: rawResponse,
    result: NativeResultDto<ReminderResponseDto>.fromJson(
      rawResponse,
      ReminderMapper.responseFromNativeData,
    ),
    isNativeResult: true,
  );
}

// 构造“通道正常但业务失败”的 NativeResult，用于区分业务错误与传输错误。
NativeInvocation<ReminderResponseDto> reminderFailureInvocation({
  required String code,
  String message = 'Reminder operation failed.',
  Map<String, dynamic>? details,
  bool retryable = false,
  String requestId = 'native-request-failure',
  bool isNativeResult = true,
}) {
  final rawResponse = <String, dynamic>{
    'ok': false,
    'data': null,
    'error': {
      'code': code,
      'message': message,
      'details': details,
      'retryable': retryable,
    },
    'contract_version': 1,
    'request_id': requestId,
  };
  return NativeInvocation<ReminderResponseDto>(
    rawResponse: rawResponse,
    result: NativeResultDto<ReminderResponseDto>.fromJson(
      rawResponse,
      ReminderMapper.responseFromNativeData,
    ),
    isNativeResult: isNativeResult,
  );
}

// 构造“没有收到合法 NativeResult”的传输失败。
NativeInvocation<ReminderResponseDto> reminderTransportFailureInvocation() {
  return NativeInvocation<ReminderResponseDto>(
    rawResponse: const {
      'flutter_diagnostic': true,
      'native_result_available': false,
      'error': {
        'code': 'NATIVE_INTERNAL_ERROR',
        'message': 'MethodChannel unavailable.',
        'details': {'method': 'reminder.cancel'},
        'retryable': false,
      },
    },
    result: NativeResultDto.localFailure<ReminderResponseDto>(
      code: 'NATIVE_INTERNAL_ERROR',
      message: 'MethodChannel unavailable.',
      details: const {'method': 'reminder.cancel'},
    ),
    isNativeResult: false,
  );
}
