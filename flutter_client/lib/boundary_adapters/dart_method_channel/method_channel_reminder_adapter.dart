import 'package:flutter/services.dart';

import '../../gateway_interfaces/reminder_native_gateway.dart';
import '../../native_contract/reminder/cancel_reminder_request_dto.dart';
import '../../native_contract/reminder/create_reminder_request_dto.dart';
import '../../native_contract/reminder/reminder_mapper.dart';
import '../../native_contract/reminder/reminder_response_dto.dart';
import '../../native_contract/reminder/schedule_pending_reminders_dto.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelReminderAdapter implements ReminderNativeGateway {
  MethodChannelReminderAdapter({
    MethodChannel channel = const MethodChannel(
      NativeMethodChannelNames.native,
    ),
  }) : _invoker = NativeMethodChannelInvoker(channel);

  final NativeMethodChannelInvoker _invoker;

  @override
  Future<NativeInvocation<ReminderResponseDto>> createReminder(
    CreateReminderRequestDto request,
  ) {
    return _invoker.invoke<ReminderResponseDto>(
      method: NativeReminderMethods.create,
      arguments: request.toJson(),
      parseData: ReminderMapper.responseFromNativeData,
    );
  }

  @override
  Future<NativeInvocation<ReminderResponseDto>> cancelReminder(
    CancelReminderRequestDto request,
  ) {
    return _invoker.invoke<ReminderResponseDto>(
      method: NativeReminderMethods.cancel,
      arguments: request.toJson(),
      parseData: ReminderMapper.responseFromNativeData,
    );
  }

  @override
  Future<NativeInvocation<SchedulePendingRemindersResponseDto>> schedulePending(
    SchedulePendingRemindersRequestDto request,
  ) {
    return _invoker.invoke<SchedulePendingRemindersResponseDto>(
      method: NativeReminderMethods.schedulePending,
      arguments: request.toJson(),
      parseData: (rawData) {
        if (rawData is! Map<String, dynamic>) {
          throw const FormatException(
            'SchedulePendingRemindersResponse data must be object.',
          );
        }
        return SchedulePendingRemindersResponseDto.fromJson(rawData);
      },
    );
  }
}
