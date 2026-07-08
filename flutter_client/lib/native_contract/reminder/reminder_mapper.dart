import 'reminder_response_dto.dart';

class ReminderMapper {
  const ReminderMapper._();

  static ReminderResponseDto responseFromNativeData(Object? rawData) {
    if (rawData is! Map<String, dynamic>) {
      throw const FormatException('ReminderResponse data must be object.');
    }
    return ReminderResponseDto.fromJson(rawData);
  }
}
