import 'reminder_response_dto.dart';
import 'reminder_list_response_dto.dart';

class ReminderMapper {
  const ReminderMapper._();

  static ReminderResponseDto responseFromNativeData(Object? rawData) {
    if (rawData is! Map<String, dynamic>) {
      throw const FormatException('ReminderResponse data must be object.');
    }
    return ReminderResponseDto.fromJson(rawData);
  }

  static ReminderListResponseDto listResponseFromNativeData(Object? rawData) {
    if (rawData is! Map<String, dynamic>) {
      throw const FormatException('ReminderListResponse data must be object.');
    }
    return ReminderListResponseDto.fromJson(rawData);
  }
}
