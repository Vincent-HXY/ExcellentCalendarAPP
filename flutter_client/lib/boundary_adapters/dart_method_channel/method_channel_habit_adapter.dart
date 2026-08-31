import 'package:flutter/services.dart';

import '../../gateway_interfaces/habit_gateway.dart';
import '../../native_contract/habit/habit_mapper.dart';
import '../../native_contract/habit/habit_request_dtos.dart';
import '../../native_contract/habit/habit_response_dtos.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelHabitAdapter implements HabitGateway {
  MethodChannelHabitAdapter({MethodChannel? channel})
    : _invoker = NativeMethodChannelInvoker(
        channel ?? const MethodChannel(NativeMethodChannelNames.native),
      );

  final NativeMethodChannelInvoker _invoker;

  @override
  Future<HabitMutationResponseDto> create(CreateHabitRequestDto request) =>
      _call(
        method: NativeHabitMethods.create,
        arguments: request.toJson(),
        parseData: HabitMapper.mutation,
      );

  @override
  Future<HabitMutationResponseDto> update(UpdateHabitRequestDto request) =>
      _call(
        method: NativeHabitMethods.update,
        arguments: request.toJson(),
        parseData: HabitMapper.mutation,
      );

  @override
  Future<HabitListResponseDto> list(ListHabitsRequestDto request) => _call(
    method: NativeHabitMethods.list,
    arguments: request.toJson(),
    parseData: HabitMapper.list,
  );

  @override
  Future<HabitDetailResponseDto> detail(GetHabitDetailRequestDto request) =>
      _call(
        method: NativeHabitMethods.detail,
        arguments: request.toJson(),
        parseData: HabitMapper.detail,
      );

  @override
  Future<HabitMutationResponseDto> end(HabitOptimisticRequestDto request) =>
      _call(
        method: NativeHabitMethods.end,
        arguments: request.toJson(),
        parseData: HabitMapper.mutation,
      );

  @override
  Future<HabitDeleteOperationResponseDto> delete(
    HabitOptimisticRequestDto request,
  ) => _call(
    method: NativeHabitMethods.delete,
    arguments: request.toJson(),
    parseData: HabitMapper.deleteOperation,
  );

  @override
  Future<HabitCheckInMutationResponseDto> checkIn(
    HabitCheckInRequestDto request,
  ) => _call(
    method: NativeHabitMethods.checkIn,
    arguments: request.toJson(),
    parseData: HabitMapper.checkInMutation,
  );

  @override
  Future<HabitCheckInMutationResponseDto> clearCheckIn(
    ClearHabitCheckInRequestDto request,
  ) => _call(
    method: NativeHabitMethods.clearCheckIn,
    arguments: request.toJson(),
    parseData: HabitMapper.checkInMutation,
  );

  @override
  Future<HabitDailyStatusListResponseDto> listDailyStatuses(
    ListHabitDailyStatusesRequestDto request,
  ) => _call(
    method: NativeHabitMethods.listDailyStatuses,
    arguments: request.toJson(),
    parseData: HabitMapper.dailyStatuses,
  );

  @override
  Future<HabitMutationResponseDto> setReminder(
    SetHabitReminderRequestDto request,
  ) => _call(
    method: NativeHabitMethods.setReminder,
    arguments: request.toJson(),
    parseData: HabitMapper.mutation,
  );

  Future<T> _call<T>({
    required String method,
    required Map<String, dynamic> arguments,
    required T Function(Object? raw) parseData,
  }) async {
    final invocation = await _invoker.invoke<T>(
      method: method,
      arguments: arguments,
      parseData: parseData,
    );
    return _unwrap(invocation);
  }

  T _unwrap<T>(NativeInvocation<T> invocation) {
    final data = invocation.result.data;
    if (invocation.result.ok && data != null) return data;
    final error = invocation.result.error;
    throw HabitGatewayFailure(
      code: error?.code ?? 'NATIVE_INTERNAL_ERROR',
      message: error?.message ?? 'Habit native invocation failed.',
      retryable: error?.retryable ?? false,
    );
  }
}
