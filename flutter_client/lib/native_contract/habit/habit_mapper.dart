import 'habit_contract_value.dart';
import 'habit_response_dtos.dart';

abstract final class HabitMapper {
  static HabitMutationResponseDto mutation(Object? raw) =>
      HabitMutationResponseDto.fromJson(
        HabitContractValue.object(raw, 'HabitMutationResponse'),
      );
  static HabitListResponseDto list(Object? raw) =>
      HabitListResponseDto.fromJson(
        HabitContractValue.object(raw, 'HabitListResponse'),
      );
  static HabitDetailResponseDto detail(Object? raw) =>
      HabitDetailResponseDto.fromJson(
        HabitContractValue.object(raw, 'HabitDetailResponse'),
      );
  static HabitCheckInMutationResponseDto checkInMutation(Object? raw) =>
      HabitCheckInMutationResponseDto.fromJson(
        HabitContractValue.object(raw, 'HabitCheckInMutationResponse'),
      );
  static HabitDeleteOperationResponseDto deleteOperation(Object? raw) =>
      HabitDeleteOperationResponseDto.fromJson(
        HabitContractValue.object(raw, 'HabitDeleteOperationResponse'),
      );
  static HabitDailyStatusListResponseDto dailyStatuses(Object? raw) =>
      HabitDailyStatusListResponseDto.fromJson(
        HabitContractValue.object(raw, 'HabitDailyStatusListResponse'),
      );
}
