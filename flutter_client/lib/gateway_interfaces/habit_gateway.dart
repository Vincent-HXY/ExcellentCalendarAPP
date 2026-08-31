import '../native_contract/habit/habit_request_dtos.dart';
import '../native_contract/habit/habit_response_dtos.dart';

abstract interface class HabitGateway {
  Future<HabitMutationResponseDto> create(CreateHabitRequestDto request);
  Future<HabitMutationResponseDto> update(UpdateHabitRequestDto request);
  Future<HabitListResponseDto> list(ListHabitsRequestDto request);
  Future<HabitDetailResponseDto> detail(GetHabitDetailRequestDto request);
  Future<HabitMutationResponseDto> end(HabitOptimisticRequestDto request);
  Future<HabitDeleteOperationResponseDto> delete(
    HabitOptimisticRequestDto request,
  );
  Future<HabitCheckInMutationResponseDto> checkIn(
    HabitCheckInRequestDto request,
  );
  Future<HabitCheckInMutationResponseDto> clearCheckIn(
    ClearHabitCheckInRequestDto request,
  );
  Future<HabitDailyStatusListResponseDto> listDailyStatuses(
    ListHabitDailyStatusesRequestDto request,
  );
  Future<HabitMutationResponseDto> setReminder(
    SetHabitReminderRequestDto request,
  );
}

class HabitGatewayFailure implements Exception {
  const HabitGatewayFailure({
    required this.code,
    required this.message,
    required this.retryable,
  });
  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => 'HabitGatewayFailure($code, $message)';
}
